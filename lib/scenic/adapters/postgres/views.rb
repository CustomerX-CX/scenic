module Scenic
  module Adapters
    class Postgres
      # Fetches defined views from the postgres connection.
      # @api private
      class Views
        def initialize(connection)
          @connection = connection
        end

        # All of the views that this connection has defined.
        #
        # This will include materialized views if those are supported by the
        # connection.
        #
        # @return [Array<Scenic::View>]
        def all
          views_from_postgres.map(&method(:to_scenic_view))
        end

        private

        attr_reader :connection

        def views_from_postgres
          connection.execute(<<-SQL)
            SELECT
              c.relname as viewname,
              pg_get_viewdef(c.oid) AS definition,
              c.relkind AS kind,
              n.nspname AS namespace
            FROM pg_class c
              LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE
              c.relkind IN ('m', 'v')
              AND c.relname NOT IN (SELECT extname FROM pg_extension)
              AND n.nspname = ANY (current_schemas(false))
            ORDER BY c.oid
          SQL
        end

        def to_scenic_view(result)
          namespace, viewname = result.values_at "namespace", "viewname"

          if namespace != "public"
            namespaced_viewname = "#{pg_identifier(namespace)}.#{pg_identifier(viewname)}"
          else
            namespaced_viewname = pg_identifier(viewname)
          end

          previous_version = Dir.entries(Rails.root.join("db", "views"))
                     .map { |name| version_regex(viewname).match(name).try(:[], "version").to_i }
                     .max
          previous_version = 1 if previous_version.zero?

          Scenic::View.new(
            name: namespaced_viewname,
            definition: Scenic::Definition.new(viewname, previous_version).to_sql,
            materialized: result["kind"] == "m",
          )
        end

        def version_regex(viewname)
          /\A#{viewname}_v(?<version>\d+)\.sql\z/
        end

        def pg_identifier(name)
          return name if name =~ /^[a-zA-Z_][a-zA-Z0-9_]*$/

          pgconn.quote_ident(name)
        end

        def pgconn
          if defined?(PG::Connection)
            PG::Connection
          else
            PGconn
          end
        end
      end
    end
  end
end
