module ArPglogicalMigration
  module ArPglogicalMigrationHelper
    def self.migrations_column_present?
      ActiveRecord::Base.connection.columns("miq_regions").any? { |c| c.name == "migrations_ran" }
    end

    class HelperARClass < ActiveRecord::Base; end

    def self.restart_subscription(s)
      c = HelperARClass.establish_connection.connection
      c.pglogical.subscription_disable(s.id)
      c.pglogical.subscription_enable(s.id)
    ensure
      HelperARClass.remove_connection
    end

    def self.update_local_migrations_ran(version, direction)
      return unless migrations_column_present?
      return unless (region = MiqRegion.my_region)

      new_migrations = ActiveRecord::SchemaMigration.normalized_versions
      new_migrations << version if direction == :up
      migrations_value = ActiveRecord::Base.connection.quote(PG::TextEncoder::Array.new.encode(new_migrations))

      ActiveRecord::Base.connection.exec_query(<<~SQL)
        UPDATE miq_regions
        SET migrations_ran = #{migrations_value}
        WHERE id = #{region.id}
      SQL
    end

    class RemoteRegionThing
      attr_reader :region, :subscription, :version
      def initialize(subscription, version)
        @region       = MiqRegion.find_by(:region => subscription.provider_region)
        @subscription = subscription
        @version      = version
      end

      def wait_for_migration?
        ArPglogicalMigrationHelper.migrations_column_present? ? !region.migrations_ran&.include?(version) : false
      end

      def wait
        return unless wait_for_migration?

        message = "Waiting for remote region #{region.region} to run migration #{version}"
        Vmdb.rails_logger.info(message)
        print(message)

        while wait_for_migration?
          print "."
          ArPglogicalMigrationHelper.restart_subscription(subscription)
          sleep(1)
          region.reload
        end

        puts
      end
    end
  end

  def migrate(direction)
    PglogicalSubscription.all.each do |s|
      ArPglogicalMigrationHelper::RemoteRegionThing.new(s, version.to_s).wait
    end

    ret = super
    ArPglogicalMigrationHelper.update_local_migrations_ran(version.to_s, direction)
    ret
  end
end

ActiveRecord::Migration.prepend(ArPglogicalMigration)
