require 'chewy/index/adapter/orm'

module Chewy
  class Index
    module Adapter
      class Mongoid < Orm
        def self.accepts?(target)
          defined?(::Mongoid::Document) && (
            (target.is_a?(Class) && target.ancestors.include?(::Mongoid::Document)) ||
              target.is_a?(::Mongoid::Criteria))
        end

        def identify(collection)
          super(collection).map { |id| id.is_a?(BSON::ObjectId) ? id.to_s : id }
        end

      private

        def cleanup_default_scope!
          Chewy.logger.warn('Default type scope order, limit and offset are ignored and will be nullified') if Chewy.logger && sort_or_limit_or_skip_options?

          @default_scope.options.delete(:limit)
          @default_scope.options.delete(:skip)
          @default_scope = @default_scope.reorder(nil)
        end

        def sort_or_limit_or_skip_options?
          @default_scope.options.values_at(:sort, :limit, :skip).compact.present?
        end

        def import_scope(scope, options)
          pluck_in_batches(scope, **options.slice(:batch_size)).map do |ids|
            yield grouped_objects(default_scope_where_ids_in(ids))
          end.all?
        end

        def import_objects(collection, options)
          direct_import = (default_scope.selector.empty? || @options[:searchable_proc]) &&
            !options[:raw_import] &&
            collection.is_a?(Array) &&
            !collection.empty? &&
            collection.all? { |item| item.is_a?(::Mongoid::Document) && item.__selected_fields.nil? }
          options[:direct_import] = direct_import unless options[:direct_import].present?
          super(collection, options)
        end

        def primary_key
          :_id
        end

        def pluck(scope, fields: [])
          scope.pluck(primary_key, *fields)
        end

        def pluck_in_batches(scope, fields: [], batch_size: nil, **options, &block)
          unless block_given?
            return enum_for(
              :pluck_in_batches,
              scope,
              fields: fields,
              batch_size: batch_size,
              **options
            )
          end

          scope.batch_size(batch_size).no_timeout.pluck(primary_key, *fields).each_slice(batch_size, &block)
        end

        def scope_where_ids_in(scope, ids)
          scope.where(primary_key.in => ids)
        end

        def all_scope
          target.all
        end

        def relation_class
          ::Mongoid::Criteria
        end

        def object_class
          ::Mongoid::Document
        end
      end
    end
  end
end
