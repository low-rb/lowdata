# frozen_string_literal: true

class LowData
  # Lays out a + chain for NestingTree. Each operand nests in the operand before it, and an array nests its expressions
  # side by side in the table before it, ending the chain:
  #   Users + Posts + Comments                # comments in posts, in users
  #   Users + [Posts + Comments, Likes]       # posts with their comments, and likes, in users
  #   Users + Posts + Likes(:user_id)         # a named foreign key reaches back: likes in users, beside posts
  # Foreign keys only link adjacent tables, so a foreign key between other tables can't change or break the chain.
  class NestingPath
    ARRAY_END_MESSAGE = 'An array ends a + chain, because it nests several tables. Put the rest of the chain in the ' \
                        'array, e.g. Users + [Posts + Comments, Orders]'
    AFTER_ARRAY_MESSAGE = '%<child>s comes after an array, so it has no single table to nest in. Put it in the array: ' \
                          '%<beside>s nests %<child>s in %<parent>s, and %<in_last>s nests it in %<last>s'

    # A node waiting for its children to be linked, and the entries from it down to the end of its chain.
    Entry = Struct.new(:node, :children, :tail, :closed) do
      def self.for(node) = new(node, [], nil, false)

      def path = self[:tail] || [self]

      def tables = node.tables
    end

    def initialize(schema:, tree:)
      @schema = schema
      @tree = tree
    end

    # A + chain is left deep, and + is associative, so a parenthesised chain's operands join the path.
    def self.segments(node:)
      return [node] unless node.is_a?(DataExpression::Join) && node.nest?

      segments(node: node.left) + segments(node: node.right)
    end

    # Returns the first segment's entry, with every other segment nested under it.
    def chain(segments:)
      root = @tree.entry(node: segments.first)
      path = segments.drop(1).reduce(root.path) { |entries, segment| attach(path: entries, segment:) }
      root.tap { |entry| entry.tail = path }
    end

    private

    # Nests a segment and returns the path to the end of the chain.
    def attach(path:, segment:)
      return siblings(path:, nodes: segment.nodes) if segment.is_a?(DataExpression::Siblings)

      child = @tree.entry(node: segment)
      raise JoinError, after_array_message(array: path.last, child:) if path.last.closed

      parent = parent(path:, child:)
      parent.children << child
      path[0..path.index { |entry| entry.equal?(parent) }] + child.path
    end

    def siblings(path:, nodes:)
      raise JoinError, ARRAY_END_MESSAGE if path.last.closed

      nodes.each { |node| path.last.children << @tree.entry(node:) }
      path.last.closed = true
      path
    end

    # The tables before the last, nearest first.
    def earlier(path:) = path[0...-1].reverse

    # The table before, unless a foreign key named in the child's round brackets points to an earlier one.
    def parent(path:, child:)
      targets = named_targets(child:)
      tables = targets.map(&:last)
      return linked!(path:, child:) if tables.empty? || (path.last.tables & tables).any?

      earlier(path:).find { |entry| (entry.tables & tables).any? } ||
        raise(JoinError, "#{targets.first.first} points to #{tables.first}, which isn't earlier in this + chain")
    end

    # Each foreign key named in the child's round brackets, as `table.column` and the table it points to. A key between
    # a join's own tables links the join, not the chain, so it's left out.
    def named_targets(child:)
      child.node.foreign_keys.flat_map do |table, columns|
        keys = @schema.foreign_keys(table:).select { |key| (key[:columns] & columns).any? && !child.tables.include?(key[:table]) }
        keys.map { |key| ["#{table}.#{key[:columns].first}", key[:table]] }
      end
    end

    # The table before, when a foreign key links the two. Otherwise it suggests nesting the child in an earlier table.
    def linked!(path:, child:)
      parent = path.last
      raise JoinError, "Can't nest #{parent.tables.join(', ')} in itself" if parent.tables == child.tables
      return parent if linked?(child, parent)

      earlier = earlier(path:).find { |entry| linked?(child, entry) }
      raise JoinError, unlinked_message(child: child.tables.first, parent: parent.tables.last, earlier: earlier&.tables&.last)
    end

    def linked?(entry, other)
      entry.tables.product(other.tables).any? { |table, other_table| @schema.linked?(table, other_table) }
    end

    # Suggests the two places in the array a table after it can go: beside its elements, or in its last one.
    def after_array_message(array:, child:)
      *elements, last = array.children
      beside = [*elements, last, child].map { |entry| chained(entry:) }
      in_last = [*elements.map { |entry| chained(entry:) }, "#{chained(entry: last)} + #{chained(entry: child)}"]
      format(AFTER_ARRAY_MESSAGE, child: child.tables.first, parent: array.tables.last, last: last.path.last.tables.last,
                                  beside: in_array(array:, elements: beside), in_last: in_array(array:, elements: in_last))
    end

    def in_array(array:, elements:) = "#{written(entry: array)} + [#{elements.join(', ')}]"

    # An array element as written, with its whole chain: `Posts + Comments`.
    def chained(entry:) = entry.path.map { |link| written(entry: link) }.join(' + ')

    # A table as written in an expression, without its brackets: `Posts`, or `(Posts & Likes)` for a join.
    def written(entry:)
      names = entry.tables.map { |table| LowData.constant_name(table) }
      names.one? ? names.first : "(#{names.join(' & ')})"
    end

    # Suggests an array, or naming the foreign key that reaches back to the earlier table.
    def unlinked_message(child:, parent:, earlier:)
      message = "No foreign key links #{child} to #{parent}"
      return message unless earlier

      names = [earlier, parent, child].map { |table| LowData.constant_name(table) }
      key = @schema.links(from: child, to: earlier).first
      "#{message}. To nest #{child} in #{earlier}, beside #{parent}, write #{names[0]} + [#{names[1]}, #{names[2]}]" +
        (key ? " or name its foreign key: #{names[2]}(:#{key[:columns].first})" : '')
    end
  end
end
