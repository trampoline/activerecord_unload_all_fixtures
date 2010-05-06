require 'set'

module Spec
  module Scenarios

    class << self
      attr_accessor :ordered_active_record_classes
      attr_accessor :table_name_set

      # iterate over all ActiveRecord models associated with db tables, deleting all rows
      # if we're inside a transaction, use delete, otherwise use truncate
      def unload_all_fixtures() 
        if ordered_active_record_classes.nil? || ordered_active_record_classes.empty?
          Spec::Scenarios::ordered_active_record_classes = ActiveRecord::Base.send(:subclasses).reject{ |klass| klass.skip_unload_fixtures? if klass.respond_to?(:skip_unload_fixtures?) }
        end
        
        Spec::Scenarios::table_name_set = ActiveRecord::Base::connection.tables.to_set

        # start with the last successful delete ordering, only re-ordering if new foreign key dependencies are found
        Spec::Scenarios::ordered_active_record_classes = unload_fixtures( Spec::Scenarios::ordered_active_record_classes, ActiveRecord::Base.connection.open_transactions == 0 )
        true
      end

      def unload_fixtures(classes, truncate=false)
        processed = []
        classes.each_with_index{ |c,i|
          if defined?(ActiveRecord::WormTable) && c.ancestors.include?(ActiveRecord::WormTable)
            tables = [c.switch_table_name] + c.table_version_names
          else
            tables = [c.table_name]
          end

          begin
            tables.each do |table_name|
              if table_name_set.include?(table_name)
                if truncate
                  ActiveRecord::Base.connection.execute("truncate table #{table_name}")
                else
                  ActiveRecord::Base.connection.execute("delete from #{table_name}")
                end
              end
            end
            processed << c
          rescue
            raise "can't remove all tables. tables remaining: #{classes.map(&:table_name).join(', ')}" unless i>0
            processed += unload_fixtures( classes[i..-1].reverse )
          end
        }
      end
    end
  end
end

