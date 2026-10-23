# frozen_string_literal: true

class LowData
  # Builds the tree Nesting loads from an expression. Tables in brackets nest directly under their table, and each
  # operand of a + chain nests in the operand before it: see NestingPath. A join nests as flat rows: see NestedJoin.
  class NestingTree
    def initialize(schema:)
      @schema = schema
      @path = NestingPath.new(schema:, tree: self)
    end

    def build(node:)
      assemble(entry: entry(node:))
    end

    # The tree whose first table is returned, so empty brackets, which select none of its columns, raise.
    def root(node:)
      root = build(node:)
      raise ArgumentError, QueryCompiler.no_columns_message(table: root.source.table) if !root.join && root.source.no_columns?

      root
    end

    # An expression's node, waiting for the children NestingPath nests in it.
    def entry(node:)
      raise JoinError, QueryCompiler::INVERSION_JOIN_MESSAGE if node.is_a?(DataExpression::Inversion)
      return ordered(node:) if node.is_a?(DataExpression::Ordered)
      return NestingPath::Entry.for(bracketed(source: node)) if node.is_a?(DataExpression::Source)
      return NestingPath::Entry.for(Nesting::Node.new(source: NestedJoin.build(node:), key: nil, link: nil, children: [])) unless node.nest?

      @path.chain(segments: NestingPath.segments(node:))
    end

    # Returns the nested key and Link for a child table. On the "one" side a key matching a foreign key column picks it,
    # so `author:` follows `author_id`, and a foreign key column named in round brackets picks between several.
    # FilterCompiler links related tables the same way.
    def link_to(parent:, child:, key:, named: {})
      to_one = @schema.links(from: parent, to: child)
      named_link = named_link(links: to_one, key:)
      return one(parent:, child:, link: named_link, key:) if named_link

      links = picked(links: to_one + @schema.links(from: child, to: parent), named:)
      raise JoinError, "No foreign key links #{child} to #{parent}" if links.empty?
      raise JoinError, many_keys_message(parent:, child:, to_one:) if links.length > 1
      return one(parent:, child:, link: links.first, key:) if to_one.include?(links.first)

      many(parent:, child:, link: links.first, key:)
    end

    private

    # A sort or limit applies to the first table of what it sorts.
    def ordered(node:)
      entry(node: node.node).tap { |entry| entry.node = entry.node.with(keys: node.keys, rows: node.rows) }
    end

    # The links whose foreign key is named in round brackets, or all of them if none is.
    def picked(links:, named:)
      picked = links.select { |link| named.values.flatten.include?(link[:columns].first) }
      picked.any? ? picked : links
    end

    # Links each entry's children to it, from the leaves up.
    def assemble(entry:)
      children = entry.children.map { |child| linked(parent: entry.node, child: assemble(entry: child), key: nil) }
      with_children(node: entry.node, children:)
    end

    # Tables in brackets nest directly under the table whose brackets they're in.
    def bracketed(source:)
      node = Nesting::Node.new(source:, key: nil, link: nil, children: [])
      with_children(node:, children: source.nested.map { |nested| linked(parent: node, child: build(node: nested.node), key: nested.key) })
    end

    # Sets a child's key and link to its parent node. A join links through its table written next to the +.
    def linked(parent:, child:, key:)
      named = parent.foreign_keys.merge(child.foreign_keys)
      table = parent.join&.linked_table(others: child.tables, schema: @schema, foreign_keys: named) || parent.source.table
      joined = child.join&.link(parent: table, key:, tree: self, schema: @schema, foreign_keys: named)
      source, key, link = joined || [child.source, *link_to(parent: table, child: child.source.table, key:, named:)]
      child.with(source:, key:, link: link.with(parent_table: parent.join && table))
    end

    def with_children(node:, children:)
      node.with(children: node.children + children).tap { |linked| check_keys!(node: linked) }
    end

    # Each nested table needs its own key, which a renamed column can't also use.
    def check_keys!(node:)
      keys = node.children.map(&:key)
      duplicate = keys.find { |key| keys.count(key) > 1 }
      raise JoinError, "Two tables nest in #{node.tables.join(', ')} as #{duplicate}. Name them, e.g. author: Users[:username]" if duplicate

      renamed = (keys & (node.join ? [] : node.source.renames.keys)).first
      raise JoinError, "#{node.tables.join(', ')} returns #{renamed} as both a renamed column and a nested table. Rename one" if renamed
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
