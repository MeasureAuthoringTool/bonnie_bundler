class CqlMeasure

  include Mongoid::Document
  include Mongoid::Timestamps

  # Metadata fields
  # TODO: Some of these are currently here for backwards compatibility, and may or not actually be available
  # once we're getting CQL packaged with HQMF
  field :cms_id, type: String
  field :title, type: String, default: ""
  field :description, type: String, default: ""
  field :hqmf_id, type: String
  field :hqmf_set_id, type: String
  field :hqmf_version_number, type: Integer

  field :measure_attributes, type: Array
  field :measure_period, type: Hash
  field :population_criteria, type: Hash
  field :populations, type: Array
  field :populations_cql_map, type: Hash

  field :episode_of_care, type: Boolean
  field :needs_finalize, type: Boolean, default: false # if true it indicates that the measure needs to have its episodes or submeasure titles defined

  # Store the original CQL as a string
  field :cql, type: String

  # Store the derived ELM as a simple hash
  # TODO: some simple documentation on the formatting of ELM (or pointers to main doc)
  field :elm, type: Hash

  # TEMPORARY: store the XML for comparison
  field :xml, type: String

  # Store the data criteria found in the measure; these are extracted before save, and we store them in both
  # the data_criteria and source_data_criteria fields to enable some simple usage of CQL measures in the same
  # contexts as we've used QDM+HQMF measures
  # TODO: determine if both are needed
  field :source_data_criteria, type: Hash
  field :data_criteria, type: Hash

  # Store a list OIDS of all value sets referenced by the measure
  field :value_set_oids, type: Array, default: []

  # Store the calculated cyclomatic complexity as a simple Hash
  # TODO: some better documentation on the formatting
  field :complexity, type: Hash

  # A measure belongs to a user
  belongs_to :user

  # Allow selection of measures by user
  scope :by_user, ->(user) { where user_id: user.id }

  # When saving calculate the cyclomatic complexity of the measure
  # TODO: Do we want to consider a measure other than "cyclomatic complexity" for CQL?
  # TODO: THIS IS NOT CYCLOMATIC COMPLEXITY, ALL MULTIPLE ELEMENT EXPRESSIONS GET COUNTED AS HIGHER COMPLEXITY, NOT JUST LOGICAL
  before_save :calculate_complexity
  def calculate_complexity
    # We calculate the complexity for each statement, and (at least for now) store the result in the same way
    # we store the complexity for QDM variables
    # TODO: consider whether this is too much of a force fit
    self.complexity = { variables: [] }

    # Recursively look through an expression to count the logical branches
    def count_expression_logical_branches(expression)
      case expression
      when nil
        0
      when Array
        expression.map { |exp| count_expression_logical_branches(exp) }.sum
      when Hash
        case expression['type']
        when 'And', 'Or', 'Not'
          count_expression_logical_branches(expression['operand'])
        when 'Query'
          # TODO: Do we need to look into the source side of the query? Can there be logical operators there?
          count_expression_logical_branches(expression['where']) + count_expression_logical_branches(expression['relationship'])
        else
          1
        end
      else
        0
      end
    end

    # Determine the complexity of each statement
    if statements = self.elm.try(:[], 'library').try(:[], 'statements').try(:[], 'def')
      statements.each do |statement|
        self.complexity[:variables] << { name: statement['name'], complexity: count_expression_logical_branches(statement['expression']) }
      end
    end

    self.complexity

  end

end
