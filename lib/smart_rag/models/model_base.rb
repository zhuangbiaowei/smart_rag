require 'sequel'

module SmartRAG
  module Models
    # Module to add FactoryBot compatibility methods to Sequel models
    module FactoryBotHelpers
      # Save! method for compatibility with FactoryBot and ActiveRecord style
      def save!(*args)
        save(*args) || raise(Sequel::ValidationFailed, errors.full_messages.join(', '))
      end

      # Create! class method for compatibility with FactoryBot
      def self.included(base)
        base.class_eval do
          def self.create!(attributes = {})
            instance = new(attributes)
            instance.save! || raise(Sequel::ValidationFailed, instance.errors.full_messages.join(', '))
            instance
          end
        end
      end

      def to_hash
        values
      end

      def to_json(*args)
        to_hash.to_json(*args)
      end
    end

    # Stub database class that allows models to be loaded without connection
    class DelayedConnection
      # Allow any method calls during model class definition
      def method_missing(method_name, *args, &block)
        # Return a stub object that accepts any method call
        # This allows Sequel's internal setup to proceed
        StubDataset.new(self)
      end

      def respond_to_missing?(method_name, include_private = false)
        true  # Pretend to respond to everything
      end

      def kind_of?(other)
        other == Sequel::Database || super
      end

      # Sequel needs these methods during model class definition
      def schema(*args)
        []  # Return empty schema
      end

      def tables(*args)
        []  # Return empty tables list
      end

      def transaction(*args)
        yield
      end

      def class_scope(*args)
        self
      end

      def from(*args)
        StubDataset.new(self)
      end
    end

    # Stub dataset class for delayed connection
    class StubDataset
      def initialize(db)
        @db = db
      end

      def method_missing(method_name, *args, **kwargs, &block)
        # Return self to chain calls
        self
      end

      def respond_to_missing?(method_name, include_private = false)
        true
      end

      def clone(*args, **kwargs)
        self
      end
    end

    # Set a stub database connection so Sequel::Model subclasses can be defined
    # This will be replaced with a real connection when SmartRAG::Models.db= is called
    begin
      Sequel::Model.db
    rescue Sequel::Error
      # No database set yet, set our stub connection
      Sequel::Model.db = DelayedConnection.new
    end

    # Base class placeholder - models inherit directly from Sequel::Model
    # This class is just for organization and documentation
    module ModelBase
    end
  end
end

