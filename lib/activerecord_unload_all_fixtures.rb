require 'set'

module ActiveRecord
  module UnloadAllFixtures

    class << self
      attr_accessor :ordered_active_record_table_names
      attr_accessor :table_name_set

      # iterate over all ActiveRecord models associated with db tables, deleting all rows
      # if we're inside a transaction, use delete, otherwise use truncate
      def unload_all_fixtures() 
        if ActiveRecord::UnloadAllFixtures::ordered_active_record_table_names.nil? || 
            ActiveRecord::UnloadAllFixtures::ordered_active_record_table_names.empty?
          klasses = ActiveRecord::Base.send(:subclasses).reject{ |klass| klass.skip_unload_fixtures if klass.respond_to?(:skip_unload_fixtures) }
          ActiveRecord::UnloadAllFixtures::ordered_active_record_table_names = klasses.map do |klass|
            if defined?(ActiveRecord::WormTable) && klass.ancestors.include?(ActiveRecord::WormTable)
              [klass.switch_table_name] + klass.table_version_names
            else
              klass.table_name
            end
          end.flatten.to_set.to_a
        end
        
        ActiveRecord::UnloadAllFixtures::table_name_set = ActiveRecord::Base::connection.tables.to_set

        # start with the last successful delete ordering, only re-ordering if new foreign key dependencies are found
        ActiveRecord::Base::without_foreign_key_checks do
          ActiveRecord::UnloadAllFixtures::ordered_active_record_table_names = delete_rows( ActiveRecord::UnloadAllFixtures::ordered_active_record_table_names, 
                                                                            ActiveRecord::Base.connection.open_transactions == 0 )
        end
        
        true
      end

      def delete_rows(table_names, truncate=false, shift_counter=table_names.size)
        processed = []
        table_names.each_with_index{ |table_name,i|
          begin
            if ActiveRecord::UnloadAllFixtures::table_name_set.include?(table_name)
              if truncate
                ActiveRecord::Base.connection.execute("truncate table #{table_name}")
              else
                ActiveRecord::Base.connection.execute("delete from #{table_name}")
              end
            end
            processed << table_name
          rescue Exception=>e
            $stderr << e.message << "\n"
            $stderr << e.backtrace << "\n"
            remaining = table_names[i..-1]
            raise "can't remove all tables. tables remaining: #{remaining.join(', ')}" unless shift_counter>0
            processed += delete_rows( remaining.unshift(remaining.pop), truncate, shift_counter-1 )
          end
        }
      end
    end
    
    module MySQL
      def disable_foreign_key_checks
        execute "set foreign_key_checks=0"
      end

      def enable_foreign_key_checks
        execute "set foreign_key_checks=1"
      end
    end
  end
end

module JdbcSpec
  module MySQL
    include ActiveRecord::UnloadAllFixtures::MySQL
  end
end

module ActiveRecord
  module ConnectionAdapters
    class AbstractAdapter
      def disable_foreign_key_checks
      end

      def enable_foreign_key_checks
      end

    end

    class MysqlAdapter
      include ActiveRecord::UnloadAllFixtures::MySQL
    end
  end

  class Base
    def self.without_foreign_key_checks
      begin
        connection.disable_foreign_key_checks
        yield
      ensure
        connection.enable_foreign_key_checks
      end
    end
  end
end
