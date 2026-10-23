# frozen_string_literal: true

class LowData
  class TableReference
    # Writes run straight away. See Writer:
    #   Posts << { title: 'Hello' }                 # Inserts, returning the new row's primary key.
    #   Posts(slug: 'hello') <= { title: 'Hello' }  # Upserts, matching on the round brackets.
    #   Posts(id: 1)[:title] = 'New'                # Updates the rows chosen by the round brackets.
    #   Posts(id: 1).delete                         # Deletes them, returning how many.
    module Writes
      def <<(rows)
        writer.insert(source: write_source, rows:)
      end

      def <=(rows)
        writer.upsert(source: write_source, rows:)
      end

      # Ruby makes an assignment return its right-hand side, so `Posts(id: 1)[:title] = 'New'` returns 'New'.
      def []=(*columns, value)
        writer.update(source: write_source, values: assignments(columns:, value:))
      end

      def delete
        writer.delete(source: write_source)
      end

      private

      def writer
        Writer.new(database: LowData.database)
      end

      def write_source
        raise ArgumentError, "~#{LowData.constant_name(table)} filters by related rows, so it can't be written to" if negated

        source
      end

      # The columns in square brackets and the value assigned to them:
      #   Posts(id: 1)[:title] = 'New'                  # One column takes a value.
      #   Posts(id: 1)[:title, :body] = ['New', '...']  # Several columns take an array of as many values.
      #   Posts(id: 1)[] = { title: 'New' }             # Empty brackets take a hash of columns and values.
      def assignments(columns:, value:)
        check_columns!(columns:)
        return assigned_hash(value:) if columns.empty?
        return { columns.first => assigned_value(value:) } if columns.one?
        return columns.zip(value).to_h if value.is_a?(Array) && value.length == columns.length

        raise ArgumentError, "#{columns.length} columns take #{columns.length} values, e.g. Posts(id: 1)[:title, :body] = ['New', '...']"
      end

      # Sequel would write a hash into one column as a condition, storing 0 or 1, so a hash for one column raises.
      def assigned_value(value:)
        return value unless value.is_a?(Hash)

        raise ArgumentError, 'One column takes one value, not a hash. To set the columns in a hash, use empty brackets, e.g. ' \
                             "Posts(id: 1)[] = { title: 'New' }"
      end

      def assigned_hash(value:)
        return value if value.is_a?(Hash) && value.any?

        raise ArgumentError, "Empty brackets take a hash of columns and values, e.g. Posts(id: 1)[] = { title: 'New' }"
      end
    end

    include Writes
  end
end
