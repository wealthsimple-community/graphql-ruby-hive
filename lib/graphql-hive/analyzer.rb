# frozen_string_literal: true

module GraphQL
  class Hive < GraphQL::Tracing::PlatformTracing
    # Fetch all users fields, input objects and enums
    class Analyzer < GraphQL::Analysis::AST::Analyzer
      def initialize(query_or_multiplex, options = {})
        super(query_or_multiplex)
        @used_fields = Set.new
        @process_variables = options.fetch(:process_variables, false)
        @provided_variables = (@process_variables && query_or_multiplex.respond_to?(:provided_variables)) ? (query_or_multiplex.provided_variables || {}) : {}
      end

      def on_enter_field(node, _parent, visitor)
        parent_type = visitor.parent_type_definition
        if parent_type&.respond_to?(:graphql_name) && node&.respond_to?(:name)
          @used_fields.add(parent_type.graphql_name)
          @used_fields.add(make_id(parent_type.graphql_name, node.name))
        end
      end

      # Visitor also calls 'on_enter_argument' when visiting input object fields in arguments
      def on_enter_argument(node, parent, visitor)
        arg_type = visitor.argument_definition.type.unwrap
        @used_fields.add(arg_type.graphql_name)

        # collect field argument path
        # input object fields won't have a "parent.name" method available
        if parent.respond_to?(:name)
          @used_fields.add(make_id(visitor.parent_type_definition.graphql_name, parent.name, node.name))
        end

        if arg_type.kind.input_object?
          collect_input_object_fields(node, arg_type, visitor.argument_definition.type)
        elsif arg_type.kind.enum?
          collect_enum_values(node, arg_type, visitor.argument_definition.type)
        end
      end

      attr_reader :used_fields

      def result
        @used_fields
      end

      private

      def collect_input_object_fields(node, input_type, full_type)
        case node.value
        when GraphQL::Language::Nodes::VariableIdentifier
          if @process_variables
            walk_variable_value(full_type, @provided_variables[node.value.name])
          else
            input_type.all_argument_definitions.map(&:graphql_name).each do |n|
              @used_fields.add(make_id(input_type.graphql_name, n))
            end
          end
        when Array
          node.value.flat_map(&:arguments).map(&:name).each do |n|
            @used_fields.add(make_id(input_type.graphql_name, n))
          end
        else
          node.value.arguments.map(&:name).each do |n|
            @used_fields.add(make_id(input_type.graphql_name, n))
          end
        end
      end

      def collect_enum_values(node, enum_type, full_type)
        case node.value
        when GraphQL::Language::Nodes::VariableIdentifier
          if @process_variables
            walk_variable_value(full_type, @provided_variables[node.value.name])
          else
            enum_type.values.values.map(&:graphql_name).each do |n|
              @used_fields.add(make_id(enum_type.graphql_name, n))
            end
          end
        when Array
          node.value.map(&:name).each do |n|
            @used_fields.add(make_id(enum_type.graphql_name, n))
          end
        else
          @used_fields.add(make_id(enum_type.graphql_name, node.value.name))
        end
      end

      # Recursively walk a variable's runtime value, marking only the schema
      # coordinates that were actually provided. Mirrors the JS client's
      # processVariables behavior, including the `!` suffix for input object
      # fields that received a non-null value.
      def walk_variable_value(type, value)
        return if value.nil?

        t = type
        t = t.of_type while t.non_null?

        if t.list?
          return unless value.is_a?(Array)
          inner = t.of_type
          value.each { |item| walk_variable_value(inner, item) }
          return
        end

        if t.kind.input_object?
          walk_input_object(t, value)
        elsif t.kind.enum?
          @used_fields.add(make_id(t.graphql_name, value.to_s))
        end
      end

      def walk_input_object(input_type, value)
        return unless value.is_a?(Hash)

        arg_defs = input_type.all_argument_definitions.each_with_object({}) { |a, h| h[a.graphql_name] = a }

        value.each do |field_name, field_value|
          key = field_name.to_s
          arg = arg_defs[key]
          next unless arg

          coord = make_id(input_type.graphql_name, key)
          @used_fields.add(coord)
          @used_fields.add("#{coord}!") unless field_value.nil?

          walk_variable_value(arg.type, field_value)
        end
      end

      def make_id(*tokens)
        tokens.join(".")
      end
    end
  end
end
