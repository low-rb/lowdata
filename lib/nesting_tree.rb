# frozen_string_literal: true

class LowData
  # Builds the tree Nesting loads from an expression. Tables in brackets nest directly under their table, and the
  # operands of a + chain nest by following foreign keys from the first operand. A join nests as flat rows: see NestedJoin.
  class NestingTree
    MULTIPLE_PATHS_MESSAGE = 'Foreign keys link %<tables>s by more than one path, so + has no single way to nest them. ' \
                             'Nest them in brackets instead, e.g. Users[:username, Posts[:title, Likes[]]]'

    def initialize(schema:)
      @schema = schema
    end

    # Builds the tree for an expression: a table with any tables nested in its brackets, or a + chain.
    def build(node:)
      raise JoinError, QueryCompiler::INVERSION_JOIN_MESSAGE if node.is_a?(DataExpression::Inversion)
      return build(node: node.node).with(keys: node.keys, rows: node.rows) if node.is_a?(DataExpression::Ordered)
      return bracketed(source: node) if node.is_a?(DataExpression::Source)
      return Nesting::Node.new(source: NestedJoin.build(node:), key: nil, link: nil, children: []) unless node.nest?

      chain(operands: operands(node:).map { |operand| build(node: operand) })
    end

    # Returns the nested key and Link for a child table. On the "one" side a key matching a foreign key column picks it,
    # so `author:` follows `author_id`. FilterCompiler links related tables the same way.
    def link_to(parent:, child:, key:)
      to_one = @schema.links(from: parent, to: child)
      named = named_link(links: to_one, key:)
      return one(parent:, child:, link: named, key:) if named

      links = to_one + @schema.links(from: child, to: parent)
      raise JoinError, "No foreign key links #{child} to #{parent}" if links.empty?
      raise JoinError, many_keys_message(parent:, child:, to_one:) if links.length > 1
      return one(parent:, child:, link: links.first, key:) if to_one.any?

      many(parent:, child:, link: links.first, key:)
    end

    private

    # A + chain is left deep, and each operand is a table, a bracketed table, a join or a parenthesised + chain.
    def operands(node:)
      return [node] unless node.is_a?(DataExpression::Join) && node.nest?

      operands(node: node.left) + [node.right]
    end

    # Tables in brackets nest directly under the table whose brackets they're in.
    def bracketed(source:)
      children = source.nested.map { |nested| linked(parent: source.table, child: build(node: nested.node), key: nested.key) }

      with_children(node: Nesting::Node.new(source:, key: nil, link: nil, children: []), children:)
    end

    # Sets a child's key and link to its parent, and a join's table that links them.
    def linked(parent:, child:, key:)
      joined = child.join&.link(parent:, key:, tree: self, schema: @schema)
      source, key, link = joined || [child.source, *link_to(parent:, child: child.source.table, key:)]
      child.with(source:, key:, link:)
    end

    # Links the operands into a tree from the first. Every operand must be linked, and only by one path.
    def chain(operands:)
      check_duplicates!(operands:)

      edges = operands.combination(2).select do |operand, other|
        operand.tables.product(other.tables).any? { |table, other_table| @schema.linked?(table, other_table) }
      end
      visited = [operands.first]
      root = attach(operand: operands.first, node: operands.first, edges:, visited:)
      check_chain!(operands:, visited:, edges:)

      root
    end

    # Nests each unvisited operand linked to `operand`. `node` is the operand with its key and link set.
    def attach(operand:, node:, edges:, visited:)
      neighbours = edges.filter_map { |pair| (pair - [operand]).first if pair.include?(operand) } - visited
      visited.concat(neighbours)
      raise JoinError, NestedJoin::PARENT_MESSAGE if node.join && neighbours.any?

      children = neighbours.map do |child|
        attach(operand: child, node: linked(parent: node.source.table, child:, key: nil), edges:, visited:)
      end

      with_children(node:, children:)
    end

    def with_children(node:, children:)
      children = node.children + children
      check_keys!(table: node.tables.join(', '), children:)
      node.with(children:)
    end

    def check_duplicates!(operands:)
      tables = operands.flat_map(&:tables)
      duplicate = tables.find { |table| tables.count(table) > 1 }
      raise JoinError, "Can't join #{duplicate} to itself. Name each in brackets, e.g. author: Users[:username]" if duplicate
    end

    def check_chain!(operands:, visited:, edges:)
      tables = operands.flat_map(&:tables)
      unreached = (operands - visited).flat_map(&:tables)
      raise JoinError, "No foreign key links #{unreached.join(' and ')} to #{(tables - unreached).join(', ')}" if unreached.any?
      raise JoinError, format(MULTIPLE_PATHS_MESSAGE, tables: tables.join(', ')) if edges.length > operands.length - 1
    end

    def check_keys!(table:, children:)
      keys = children.map(&:key)
      duplicate = keys.find { |key| keys.count(key) > 1 }
      raise JoinError, "Two tables nest in #{table} as #{duplicate}. Name them, e.g. author: Users[:username]" if duplicate
    end

    def named_link(links:, key:)
      named = links.select { |link| key && [key, :"#{key}_id"].include?(link[:columns].first) }
      named.first if named.one?
    end

    # `user_id` nests as `user:`, like the association name in most ORMs.
    def one(parent:, child:, link:, key:)
      column, foreign_key = sole_columns(parent:, child:, link:)
      key ||= column.to_s.end_with?('_id') ? column.to_s.delete_suffix('_id').to_sym : child
      [key, Nesting::Link.new(parent_column: column, child_column: foreign_key, many: false)]
    end

    def many(parent:, child:, link:, key:)
      column, foreign_key = sole_columns(parent:, child:, link:)
      [key || child, Nesting::Link.new(parent_column: foreign_key, child_column: column, many: true)]
    end

    def sole_columns(parent:, child:, link:)
      columns, keys = link.values_at(:columns, :keys)
      raise JoinError, "Nesting doesn't support composite foreign keys between #{parent} and #{child}" if columns.length > 1

      [columns.first, keys.first]
    end

    def many_keys_message(parent:, child:, to_one:)
      message = "More than one foreign key links #{parent} and #{child}"
      return message if to_one.empty?

      names = to_one.map { |link| "#{link[:columns].first.to_s.delete_suffix('_id')}: #{LowData.constant_name(child)}[]" }
      "#{message}. Name the one to follow, e.g. #{names.sort.join(' or ')}"
    end
  end
end
