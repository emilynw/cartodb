# encoding: utf-8

module CartoDB
  module Overlay
    class Presenter
      def initialize(overlay)
        @overlay = overlay
      end #initialize

      def to_poro
        {
          type:     overlay.type,
          order:    overlay.order,
          options:  JSON.parse(overlay.options),
          template: overlay.template
        }
      end

      private

      attr_reader :overlay
    end #Presenter
  end #Overlay
end # CartoDB

