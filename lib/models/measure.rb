class Measure
  include Mongoid::Document
  include Mongoid::Timestamps

  DEFAULT_EFFECTIVE_DATE = Time.gm(2012,12,31,23,59).to_i
  MP_START_DATE = Time.gm(2012,1,1,0,0).to_i
  TYPES = ["ep", "eh"]

  store_in collection: 'draft_measures'

  field :id, type: String
  field :measure_id, type: String
  field :hqmf_id, type: String # should be using this one as primary id!!
  field :hqmf_set_id, type: String
  field :hqmf_version_number, type: Integer
  field :cms_id, type: String
  field :title, type: String
  field :description, type: String
  field :type, type: String
  field :category, type: String

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
  field :measure_attributes, type: Hash
  field :populations, type: Array
  field :preconditions, type: Hash

  field :value_set_oids, type: Array, default: []

  field :map_fns, type: Array, default: []

  # Cache the generated JS code, with optional options to manipulate cached result                                                            
  def map_fn(population_index, options = {})
    options.assert_valid_keys :clear_db_cache, :cache_result_in_db, :check_crosswalk
    # Defaults are: don't clear the cache, do cache the result in the DB, use user specified crosswalk setting
    options.reverse_merge! clear_db_cache: false, cache_result_in_db: true, check_crosswalk: !!self.user.crosswalk_enabled
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
  has_and_belongs_to_many :records, :inverse_of => nil

  scope :by_measure_id, ->(id) { where({'measure_id'=>id }) }
  scope :by_user, ->(user) { where({'user_id'=>user.id}) }
  scope :by_type, ->(type) { where({'type'=>type}) }

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
    @value_sets ||= HealthDataStandards::SVS::ValueSet.in(oid: value_set_oids)
    @value_sets
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
