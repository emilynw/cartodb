# encoding: utf-8

require_relative 'segment'
require_relative 'hubspot'

module Carto
  module Tracking
    module Formats
      class Internal
        def initialize(hash)
          @hash = hash ? hash.with_indifferent_access : Hash.new
        end

        # Symbol should be provided as a snake-case'd version the record's model class name.
        # The id of said record should be provided with key: snake-case'd identifier + '_id'
        # Only Carto:: records allowed!
        #  Ex.: :super_duper_mdoel -> Carto::SuperDuperModel; { super_duper_model_id: xxx }
        def fetch_record!(symbol)
          symbol_string = symbol.to_s.downcase
          record_class_name = "Carto::#{symbol_string.camelize}".freeze
          record_id_key = "#{symbol_string}_id".freeze
          record_id = @hash[record_id_key]

          record_class_name.constantize.find(record_id)
        rescue
          record_id ? (raise Carto::LoadError.new("#{record_class_name} not found")) : nil
        end

        def to_hash
          @hash
        end

        def to_segment
          user = fetch_record!(:user)
          visualization = fetch_record!(:visualization)

          Carto::Tracking::Formats::Segment.new(user: user,
                                                visualization: visualization,
                                                hash: @hash).to_hash
        end

        def to_hubspot
          user = fetch_record!(:user)

          Carto::Tracking::Formats::Hubspot.new(email: user.email).to_hash
        end
      end
    end
  end
end
