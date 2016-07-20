class Measure
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Attributes::Dynamic
  
  DEFAULT_EFFECTIVE_DATE = Time.gm(2012,12,31,23,59).to_i
  MP_START_DATE = Time.gm(2012,1,1,0,0).to_i
  TYPES = ["ep", "eh"]

  store_in collection: 'draft_measures'

  field :id, type: String
  field :measure_id, type: String
  field :hqmf_id, type: String # should be using this one as primary id!!
  field :hqmf_set_id, type: String
  field :hqmf_version_number, type: String
  field :cms_id, type: String
  field :title, type: String
  field :description, type: String
  field :type, type: String
  field :category, type: String, default: 'uncategorized'

  field :episode_of_care, type: Boolean
  field :continuous_variable, type: Boolean
  field :episode_ids, type: Array # of String ids
  field :custom_functions, type: Hash # stores a custom function for a population criteria (used only in ADE_TTR for observation)
  field :force_sources, type: Array # stores a list of source data criteria to force method creation for (used only in ADE_TTR for LaboratoryTestResultInr)

  field :needs_finalize, type: Boolean, default: false # if true it indicates that the measure needs to have its episodes or submeasure titles defined

  field :published, type: Boolean
  field :publish_date, type: Date
  field :version, type: Integer

  field :population_criteria, type: Hash
  field :data_criteria, type: Hash, default: {}
  field :source_data_criteria, type: Hash, default: {}
  field :measure_period, type: Hash
  field :measure_attributes, type: Array
  field :populations, type: Array
  field :preconditions, type: Hash

  field :value_set_oids, type: Array, default: []

  field :map_fns, type: Array, default: []

  field :complexity, type: Hash
  field :measure_logic, type: Array

  #make sure that the use has a bundle associated with them
  before_save :set_continuous_variable

  # Cache the generated JS code, with optional options to manipulate cached result                                                            
  def map_fn(population_index, options = {})
    options.assert_valid_keys :clear_db_cache, :cache_result_in_db, :check_crosswalk
    # Defaults are: don't clear the cache, do cache the result in the DB, use user specified crosswalk setting
    options.reverse_merge! clear_db_cache: false, cache_result_in_db: true, check_crosswalk: !!self.user.try(:crosswalk_enabled)
    self.map_fns[population_index] = nil if options[:clear_db_cache]
    self.map_fns[population_index] ||= as_javascript(population_index, options[:check_crosswalk])
    save if changed? && options[:cache_result_in_db]
    self.map_fns[population_index]
  end

  # Generate and cache all the javascript for the measure, optionally clearing the cache first
  def generate_js(options = {})
    populations.each_with_index { |p, idx| map_fn(idx, options) }
  end

  # Clear any cached JavaScript, forcing it to be generated next time it's requested
  def clear_cached_js
    self.map_fns.map! { nil }
    self.save
  end

  belongs_to :user
  belongs_to :bundle, class_name: "HealthDataStandards::CQM::Bundle"
  has_and_belongs_to_many :records, :inverse_of => nil

  scope :by_measure_id, ->(id) { where({'measure_id'=>id }) }
  scope :by_user, ->(user) { where({'user_id'=>user.id}) }
  scope :by_type, ->(type) { where({'type'=>type}) }

  index "user_id" => 1
  # Find the measures matching a patient
  def self.for_patient(record)
    where user_id: record.user_id, hqmf_set_id: { '$in' => record.measure_ids }
  end

  TYPE_MAP = {
    'problem' => 'conditions',
    'encounter' => 'encounters',
    'labresults' => 'results',
    'procedure' => 'procedures',
    'medication' => 'medications',
    'rx' => 'medications',
    'demographics' => 'characteristic',
    'derived' => 'derived'
  }

  # Returns the hqmf-parser's ruby implementation of an HQMF document.
  # Rebuild from population_criteria, data_criteria, and measure_period JSON
  def as_hqmf_model
    json = {
      "id" => self.measure_id,
      "title" => self.title,
      "description" => self.description,
      "population_criteria" => self.population_criteria,
      "data_criteria" => self.data_criteria,
      "source_data_criteria" => self.source_data_criteria,
      "measure_period" => self.measure_period,
      "attributes" => self.measure_attributes,
      "populations" => self.populations,
      "hqmf_id" => self.hqmf_id,
      "hqmf_set_id" => self.hqmf_set_id,
      "hqmf_version_number" => self.hqmf_version_number,
      "cms_id" => self.cms_id
    }

    HQMF::Document.from_json(json)
  end

  def value_sets
    options = { oid: value_set_oids }
    options[:user_id] = user.id if user?
    @value_sets ||= HealthDataStandards::SVS::ValueSet.in(options)
    @value_sets
  end

  def all_data_criteria
    as_hqmf_model.all_data_criteria
  end

  def as_javascript(population_index, check_crosswalk=false)
    options = {
      value_sets: value_sets,
      episode_ids: episode_ids,
      continuous_variable: continuous_variable,
      force_sources: force_sources,
      custom_functions: custom_functions,
      check_crosswalk: check_crosswalk
    }

    HQMF2JS::Generator::Execution.logic(as_hqmf_model, population_index, options)
  end

  def set_continuous_variable
    self.continuous_variable = populations.map {|x| x.keys}.flatten.uniq.include? HQMF::PopulationCriteria::MSRPOPL
    true
  end

  ############################## Measure Criteria Keys ##############################

  # Given a data criteria, return the list of all data criteria keys referenced within, either through
  # children criteria or temporal references; this includes the passed in criteria reference
  def data_criteria_criteria_keys(criteria_reference)
    criteria_keys = [criteria_reference]
    if criteria = self.data_criteria[criteria_reference]
      if criteria['children_criteria'].present?
        criteria_keys.concat(criteria['children_criteria'].map { |c| data_criteria_criteria_keys(c) }.flatten)
      end
      if criteria['temporal_references'].present?
        criteria_keys.concat(criteria['temporal_references'].map { |tr| data_criteria_criteria_keys(tr['reference']) }.flatten)
      end
    end
    criteria_keys
  end

  # Given a precondition, return the list of all data criteria keys referenced within
  def precondition_criteria_keys(precondition)
    if precondition['preconditions'] && precondition['preconditions'].size > 0
      precondition['preconditions'].map { |p| precondition_criteria_keys(p) }.flatten
    elsif precondition['reference']
      data_criteria_criteria_keys(precondition['reference'])
    else
      []
    end
  end

  # Return the list of all data criteria keys in this measure, indexed by population code
  def criteria_keys_by_population
    criteria_keys_by_population = {}
    population_criteria.each do |name, precondition|
      criteria_keys_by_population[name] = precondition_criteria_keys(precondition).reject { |ck| ck == 'MeasurePeriod' }
    end
    criteria_keys_by_population
  end

  ############################## Measure Complexity Analysis ##############################

  def precondition_complexity(precondition)
    # We want to calculate the number of branching paths; we can do that by simply counting the leaf nodes.
    # Any children of this particular node can appear either through child preconditions or by reference to a
    # data criteria. ASSERTION: a precondition can never both have child preconditions and a data criteria.
    if precondition['preconditions'] && precondition['preconditions'].size > 0
      precondition['preconditions'].map { |p| precondition_complexity(p) }.sum
    elsif precondition['reference']
      data_criteria_complexity(precondition['reference'])
    else
      1
    end
  end

  def data_criteria_complexity(criteria_reference, options = {})
    options.reverse_merge! calculating_variable: false
    # We want to calculate the number of branching paths, which we can normally do by counting leaf nodes.
    # This is more complicated for data criteria because, in addition to direct children, the criteria can
    # also have temporal references, which can themselves branch. Our approach is to calculate an initial
    # number of leaf nodes through looking at direct children and then seeing if any additional leaves are
    # added through temporal references. A temporal reference that doesn't branch doesn't add a leaf node.
    # Finally, this reference may be a variable, in which case we consider this a leaf node *unless* we are
    # explicitly calculating the complexity of the variable itself
    if criteria = self.data_criteria[criteria_reference]
      complexity = if criteria['children_criteria'].present? && (!criteria['variable'] || options[:calculating_variable])
                     criteria['children_criteria'].map { |c| data_criteria_complexity(c) }.sum
                   else
                     1
                   end
      complexity + if criteria['temporal_references'].present?
                     criteria['temporal_references'].map { |tr| data_criteria_complexity(tr['reference']) - 1 }.sum
                   else
                     0
                   end
    else
      1
    end
  end

  # Calculate the complexity of the measure based on cyclomatic complexity (which for simple logical
  # constructs as used to specify measure populations generally means counting clauses); we calculate
  # the complexity separately for populations and individual variables; this is called when the
  # measure is saved so that the calculated complexity is cached in the DB
  before_save :calculate_complexity
  def calculate_complexity
    self.complexity = { populations: [], variables: [] }
    self.population_criteria.each do |name, precondition|
      complexity = precondition_complexity(precondition)
      self.complexity[:populations] << { name: name, complexity: complexity }
    end
    self.source_data_criteria.each do |reference, criteria|
      next unless criteria['variable']
      name = criteria['description']
      complexity = data_criteria_complexity(reference, calculating_variable: true)
      self.complexity[:variables] << { name: name, complexity: complexity }
    end
    self.complexity
  end

  #########################################################################################

  ############################## Measure Change Analysis ##############################

  # Extract the measure logic text; this is also cached in the DB
  before_save :extract_measure_logic
  def extract_measure_logic
    self.measure_logic = []
    # There are occasional issues extracting measure logic; while we want to fix them we also don't want logic
    # extraction issues to hold up loading or updating a measure
    begin
      self.measure_logic.concat HQMF::Measure::LogicExtractor.new().population_logic(self)
    rescue => e
      self.measure_logic << "Error parsing measure logic: #{e.message}"
    end
    self.measure_logic
  end

  # Compute a simplified diff hash for Complexity Dashboard usage; stored within measure.latest_diff
  def diff(other)
    HQMF::Measure::LogicExtractor.get_measure_logic_diff(self,other,true)
  end

  #########################################################################################

  def measure_json(population_index=0,check_crosswalk=false)
    options = {
      value_sets: value_sets,
      episode_ids: episode_ids,
      continuous_variable: continuous_variable,
      force_sources: force_sources,
      custom_functions: custom_functions,
      check_crosswalk: check_crosswalk
    }
        population_index ||= 0
        json = {
          id: self.hqmf_id,
          nqf_id: self.measure_id,
          hqmf_id: self.hqmf_id,
          hqmf_set_id: self.hqmf_set_id,
          hqmf_version_number: self.hqmf_version_number,
          cms_id: self.cms_id,
          name: self.title,
          description: self.description,
          type: self.type,
          category: self.category,
          map_fn: HQMF2JS::Generator::Execution.measure_js(self.as_hqmf_model, population_index, options),
          continuous_variable: self.continuous_variable,
          episode_of_care: self.episode_of_care,
          hqmf_document:  self.as_hqmf_model.to_json
        }
        
        if (self.populations.count > 1)
          sub_ids = ('a'..'az').to_a
          json[:sub_id] = sub_ids[population_index]
          population_title = self.populations[population_index]['title']
          json[:subtitle] = population_title
          json[:short_subtitle] = population_title
        end

        if self.continuous_variable
          observation = self.population_criteria[self.populations[population_index][HQMF::PopulationCriteria::OBSERV]]
          json[:aggregator] = observation['aggregator']
        end
        
        json[:oids] = self.value_sets.map{|value_set| value_set.oid}.uniq
        
        population_ids = {}
        HQMF::PopulationCriteria::ALL_POPULATION_CODES.each do |type|
          population_key = self.populations[population_index][type]
          population_criteria = self.population_criteria[population_key]
          if (population_criteria)
            population_ids[type] = population_criteria['hqmf_id']
          end
        end
        stratification = self['populations'][population_index]['stratification']
        if stratification
          population_ids['stratification'] = stratification 
        end
        json[:population_ids] = population_ids
        json
      end
end
