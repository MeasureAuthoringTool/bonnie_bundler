module HQMF
  module ValueSet

    class Version1
      ORGANIZATION_INDEX = 0
      OID_INDEX = 1
      CONCEPT_INDEX = 3
      CATEGORY_INDEX = 4
      CODE_SET_INDEX =5
      VERSION_INDEX = 6
      CODE_INDEX = 7
      DESCRIPTION_INDEX = 8
 
      DEFAULT_SHEET = 1
      SUPPLEMENTAL_SHEET = 2

      def self.get_display_name(row)
        display_name = normalize_names(row[CATEGORY_INDEX],row[CONCEPT_INDEX]).titleize
      end
      # Break all the supplied strings into separate words and return the resulting list as a
      # new string with each word separated with '_'
      def self.normalize_names(*components)
        name = []
        components.each do |component|
          component ||= ''
          name.concat component.gsub(/\W/,' ').split.collect { |word| word.strip.downcase }
        end
        name.join '_'
      end

    end

    class Version2
      ORGANIZATION_INDEX = 0
      OID_INDEX = 1
      CONCEPT_INDEX = 3
      CODE_SET_INDEX =4
      VERSION_INDEX = 5
      CODE_INDEX = 6
      DESCRIPTION_INDEX = 7

      DEFAULT_SHEET = 0
      SUPPLEMENTAL_SHEET = 1

      def self.get_display_name(row)
        display_name = row[CONCEPT_INDEX].titleize
      end

    end

    # Version 3 adds version and expansion identifier columns to Version 2
    class Version3
      ORGANIZATION_INDEX = 0 # Value Set Developer
      OID_INDEX = 1 # Value Set OID
      CONCEPT_INDEX = 3 # Value Set Name
      CODE_SET_INDEX = 4 # Code System
      VERSION_INDEX = 5 # Code System Version
      CODE_INDEX = 6 # Code
      VERSION_IDENTIFIER_INDEX = 7 # Version
      EXPANSION_IDENTIFIER_INDEX = 8 # Expansion Identifier
      DESCRIPTION_INDEX = 9 # Descriptor
 
      DEFAULT_SHEET = 0
      SUPPLEMENTAL_SHEET = 1

      def self.get_display_name(row)
        display_name = row[CONCEPT_INDEX].titleize
      end

    end

    # Version 4 just shuffles some fields around
    class Version4
      ORGANIZATION_INDEX = 0 # Value Set Developer
      OID_INDEX = 1 # Value Set OID
      VERSION_IDENTIFIER_INDEX = 2 # Version
      EXPANSION_IDENTIFIER_INDEX = 3 # Expansion Identifier
      CONCEPT_INDEX = 5 # Value Set Name
      CODE_SET_INDEX = 6 # Code System
      VERSION_INDEX = 7 # Code System Version
      CODE_INDEX = 8 # Code
      DESCRIPTION_INDEX = 9 # Descriptor

      DEFAULT_SHEET = 0
      SUPPLEMENTAL_SHEET = 1

      def self.get_display_name(row)
        display_name = row[CONCEPT_INDEX].titleize
      end

    end

    class Parser

      attr_accessor :child_oids
      attr_accessor :parent_oids
  
      GROUP_CODE_SET = "GROUPING"
  
      CODE_SYSTEM_NORMALIZER = {
        'ICD-9'=>'ICD-9-CM',
        'ICD9CM'=>'ICD-9-CM',
        'ICD9PCS'=>'ICD-9-PCS',
        'ICD-10'=>'ICD-10-CM',
        'ICD10CM'=>'ICD-10-CM',
        'ICD10PCS'=>'ICD-10-PCS',
        'HL7 (2.16.840.1.113883.5.1)'=>'HL7',
        'SNOMEDCT'=>'SNOMED-CT',
        'CDCREC'=>'CDC Race',
        'RXNORM'=>'RxNorm'
      }
      IGNORED_CODE_SYSTEM_NAMES = ['Grouping', 'GROUPING' ,'HL7', "Administrative Sex", 'CDC']
  
      # import an excel matrix array into mongo
      def parse(file)
        @value_set_models = {}

        book = HQMF::ValueSet::Parser.book_by_format(file)
        @constants = if book.sheets.count > 2
                       Version1.new.class
                     elsif book.sheet(0).row(1).size < 10
                       Version2.new.class
                     elsif book.sheet(0).row(1)[3] == 'Value Set Name'
                       Version3.new.class
                     else
                       Version4.new.class
                     end

        extract_value_sets(book, @constants::DEFAULT_SHEET)
        book = HQMF::ValueSet::Parser.book_by_format(file)
        extract_value_sets(book, @constants::SUPPLEMENTAL_SHEET)
        @value_set_models.values
      end

      def self.book_by_format(file_path)
        if file_path =~ /xls$/
          Roo::Excel.new(file_path, file_warning: :ignore)
        elsif file_path =~ /xlsx$/
          Roo::Excelx.new(file_path, file_warning: :ignore)
        else
          raise "File: #{file_path} does not end in .xls or .xlsx"
        end
      end

      private

      def normalize_code_system(code_system_name)
        code_system_name = CODE_SYSTEM_NORMALIZER[code_system_name] if CODE_SYSTEM_NORMALIZER[code_system_name]
        return code_system_name if IGNORED_CODE_SYSTEM_NAMES.include? code_system_name
        oid = HealthDataStandards::Util::CodeSystemHelper.oid_for_code_system(code_system_name)
        puts "\tbad code system name: #{code_system_name}" unless oid
        code_system_name
      end
  
      # turn a single cpt code range into a set of codes, otherwise return the code as an array
      def extract_code(code, set)
        code.strip!
        if set=='CPT' && code.include?('-')
          eval(code.strip.gsub('-','..')).to_a.collect { |i| i.to_s }
        else
          [code]
        end
      end
  
      # pull all the value sets and fill out the parents
      def extract_value_sets(book, sheet_index)

        book.default_sheet=book.sheets[sheet_index]
        return if book.last_row.nil? || book.last_row < 2

        @child_oids = Set.new
        @parent_oids = Set.new

        (2..book.last_row).each do |row_index|
          extract_row(book.row(row_index))
        end

        fill_out_parents

      end

      # turn a row array into a value set model stored in @value_set_models
      # parents still need to be filled out after the fact
      def extract_row(row)

        oid = row[@constants::OID_INDEX].strip.gsub(/[^0-9\.]/i, '')

        # skip rows with no oid
        return if oid.nil? || oid.empty?

        existing_vs = @value_set_models[oid]

        version = row[@constants::VERSION_INDEX]
        if existing_vs.nil?
          # display_name = normalize_names(row[CATEGORY_INDEX],row[CONCEPT_INDEX]).titleize
          display_name = row[@constants::CONCEPT_INDEX].titleize
          existing_vs = HealthDataStandards::SVS::ValueSet.new({oid: oid, display_name: display_name, version: version ,concepts: []})
          @value_set_models[oid] = existing_vs
        end

        codes = extract_code(row[@constants::CODE_INDEX].to_s, row[@constants::CODE_SET_INDEX])
        code_system_name = normalize_code_system(row[@constants::CODE_SET_INDEX])
        description = row[@constants::DESCRIPTION_INDEX]

        codes.each do |code|
          concept = HealthDataStandards::SVS::Concept.new({code: code, code_system_name: code_system_name, code_system_version: version, display_name: description})
          existing_vs.concepts << concept
        end

        if (code_system_name.upcase == GROUP_CODE_SET)
          @parent_oids << oid
        else
          @child_oids << oid
        end
      end
  
      def fill_out_parents
        @parent_oids.each do |parent_oid|
          parent_vs = @value_set_models[parent_oid]
          concepts = parent_vs.concepts.map do |c| 
            if @value_set_models[c.code]
              @value_set_models[c.code].concepts
            else
              error_message = "value set #{c.code} is referenced by parent value set #{parent_oid} but not present"
              raise Measures::ValueSetException.new "Error Parsing Value Sets: #{error_message}"
            end
          end
          parent_vs.concepts = concepts.flatten!
        end
      end

  
    end
  end
end
