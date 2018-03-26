require 'rest_client'
require 'uri'

module Util
  module VSAC

    # Generic VSAC related exception.
    class VSACError < StandardError
    end

    # Error represnting a not found response from the API. Includes OID for reporting to user.
    class VSNotFoundError < VSACError
      attr_reader :oid
      def initialize(message, oid)
        super(message)
        @oid = oid
      end
    end

    # Error represnting a response from the API that had no concepts.
    class VSEmptyError < VSACError
      attr_reader :oid
      def initialize(message, oid)
        super(message)
        @oid = oid
      end
    end

    # Raised when the ticket granting ticket has expired.
    class VSACTicketExpiredError < VSACError
      def initialize
        super('VSAC session expired. Please re-enter credentials and try again.')
      end
    end

    # Raised when the user credentials were invalid.
    class VSACInvalidCredentialsError < VSACError
      def initialize
        super('VSAC ULMS credentials are invalid.')
      end
    end

    # Raised when a call requiring auth is attempted when no ticket_granting_ticket or credentials were provided.
    class VSACNoCredentialsError < VSACError
      def initialize
        super('VSAC ULMS credentials were not provided.')
      end
    end

    # Raised when the arguments passed in are bad.
    class VSACArgumentError < VSACError
    end

    class VSACAPI
      DEFAULT_PROGRAM = "CMS eCQM"

      # The ticket granting that will be obtained if needed. Accessible so it may be stored in user session.
      # Is a hash of the :ticket and time it :expires.
      attr_reader :ticket_granting_ticket

      ##
      # Creates a new VSACAPI. If credentials were provided they are checked now. If no credentials
      # are provided then the API can still be used for utility methods.
      #
      # Options for the API are passed in as a hash.
      # * config -
      def initialize(options)
        # check that :config exists and has needed fields
        if !options.has_key?(:config) || options[:config] == nil
          raise VSACArgumentError.new("Required param :config is missing or empty.")
        else
          symbolized_config = options[:config].symbolize_keys
          if check_config symbolized_config
            @config = symbolized_config
          else
            raise VSACArgumentError.new("Required param :config is missing required URLs.")
          end
        end

        # if a ticket_granting_ticket was passed in, check it and raise errors if found
        # username and password will be ignored
        if options.has_key?(:ticket_granting_ticket)
          tgt = options[:ticket_granting_ticket]
          if !(tgt.has_key?(:ticket) && tgt.has_key?(:expires))
            raise VSACArgumentError.new("Optional param :ticket_granting_ticket is missing :ticket or :expires")
          end

          # check if it has expired
          if Time.now > tgt[:expires]
            raise VSACTicketExpiredError.new
          end

          # ticket granting ticket looks good
          @ticket_granting_ticket = { ticket: tgt[:ticket], expires: tgt[:expires] }

        # if username and password were provided use them to get a ticket granting ticket
        elsif !options[:username].nil? && !options[:password].nil?
          @ticket_granting_ticket = get_ticket_granting_ticket(options[:username], options[:password])
        end
      end

      ##
      # Gets the list of profiles. This may be used without credentials.
      #
      # Returns a list of profile names.
      def get_profiles
        profiles_response = RestClient.get("#{@config[:utility_url]}/profiles")
        profiles = []

        # parse xml response and get text content of each profile element
        doc = Nokogiri::XML(profiles_response)
        profile_list = doc.at_xpath("/ProfileList")
        profile_list.xpath("//profile").each do |profile|
          profiles << profile.text
        end

        return profiles
      end

      ##
      # Gets the list of programs. This may be used without credentials.
      #
      # Returns a list of program names.
      def get_programs
        programs_response = RestClient.get("#{@config[:utility_url]}/programs")
        program_names = []

        # parse json response and return the names of the programs
        programs_info = JSON.parse(programs_response)['Program']
        programs_info.each do |program|
          program_names << program['name']
        end

        return program_names
      end

      ##
      # Gets the details for a program. This may be used without credentials.
      #
      # Returns the JSON parsed response for program details.
      def get_program_details(program = nil)
        # if no program was provided use the one in the config or default in constant
        if program == nil
          program = @config.fetch(:program, DEFAULT_PROGRAM)
        end

        # parse json response and return it
        return JSON.parse(RestClient.get("#{@config[:utility_url]}/program/#{URI.escape(program)}"))
      end

      ##
      # Gets the releases for a program. This may be used without credentials.
      #
      # Returns a list of releases in a program.
      def get_releases_for_program(program = nil)
        program_details = get_program_details(program)
        releases = []

        # pull just the release names out
        program_details['release'].each do |release|
          releases << release['name']
        end

        return releases
      end

      ##
      # Gets a valueset. This requires credentials.
      #
      def get_valueset(oid, options = {})
        # base parameter oid is always needed
        params = { id: oid }

        # release parameter, should be used moving forward
        params[:release] = options[:release] if options.has_key?(:release)

        # profile parameter, may be needed for getting draft value sets
        if options.has_key?(:profile)
          params[:profile] = options[:profile]
          if options.has_key?(:include_draft)
            params[:includeDraft] = if !!options[:include_draft] then 'yes' else 'no' end
          end
        else
          if options.has_key?(:include_draft)
            raise VSACArgumentError.new("Option :include_draft requires :profile to be provided.")
          end
        end

        # version parameter, rarely used
        if options.has_key?(:version)
          params[:version] = options[:version]
        end

        # get a new service ticket
        params[:ticket] = get_ticket

        # run request
        begin
          value_set_response = RestClient.get("#{@config[:content_url]}/RetrieveMultipleValueSets", params: params)
        rescue RestClient::ResourceNotFound
          raise VSNotFoundError.new("Value set not found.", oid)
        end
      end

      private

      def get_ticket
        # if there is no ticket granting ticket then we should raise an error
        raise VSACNoCredentialsError.new unless @ticket_granting_ticket
        # if the ticket granting ticket has expired, throw an error
        raise VSACTicketExpiredError.new if Time.now > @ticket_granting_ticket[:expires]

        # attempt to get a ticket
        begin
          ticket = RestClient.post("#{@config[:auth_url]}/Ticket/#{@ticket_granting_ticket[:ticket]}", service: "http://umlsks.nlm.nih.gov")
          return ticket
        rescue RestClient::Unauthorized
          @ticket_granting_ticket[:expires] = Time.now
          raise VSACTicketExpiredError.new
        end
      end

      def get_ticket_granting_ticket(username, password)
        begin
          ticket = RestClient.post("#{@config[:auth_url]}/Ticket", username: username, password: password)
          return { ticket: ticket, expires: Time.now + 8.hours }
        rescue RestClient::Unauthorized
          raise VSACInvalidCredentialsError.new
        end
      end

      # Checks to ensure the API config has all necessary fields
      def check_config(config)
        return config != nil &&
               config.has_key?(:auth_url) &&
               config.has_key?(:content_url) &&
               config.has_key?(:utility_url)
      end

    end

  end
end
