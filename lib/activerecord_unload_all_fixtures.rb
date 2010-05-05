require 'set'

module Spec
  module Scenarios

    class << self
      attr_accessor :ordered_active_record_classes
      attr_accessor :table_name_set

      # Kill kill kill all the fixtures. Fixtures are evil, they must die.
      # Use introspection on the db tables to run delete_all on each class. 
      # Note that models that don't use the Railsy pluralized table names will break this pattern.
      # We keep alternating the order of the tables that we scrub until all tables are wiped, in order to circumnavigate FK constraints. 
      # Worst case is that we try each table i.e. O(n^2), but this is still way faster than using destroy_all.
      def unload_all_fixtures() 
        if ordered_active_record_classes.nil? || ordered_active_record_classes.empty?
          Spec::Scenarios::ordered_active_record_classes = ActiveRecord::Base.connection.tables.map {|t| 
            t.downcase.singularize.camelize.constantize rescue nil
          }.compact.select {|cls| cls.ancestors.include?(ActiveRecord::Base)}

          # offline lock causes problems when running specs in jruby
          # (offline lock table will get locked, so insert lock from other thread will block)
          Spec::Scenarios::ordered_active_record_classes -= [ 'OfflineLock'.constantize ] if RUBY_PLATFORM =~ /java/
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
            tables = [c.switch_table_name,c.table_version_names]
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

