# frozen_string_literal: true

require "spec_helper"

RSpec.describe "GraphQL::Hive::Analyzer" do
  subject(:used_fields) do
    query = GraphQL::Query.new(schema, query_string, variables: variables)
    analyzer = GraphQL::Hive::Analyzer.new(query, process_variables: process_variables)
    visitor = GraphQL::Analysis::AST::Visitor.new(
      query: query,
      analyzers: [analyzer],
      timeout: nil
    )

    visitor.visit
    analyzer.used_fields.to_a
  end

  let(:variables) { {} }
  let(:process_variables) { false }

  let(:schema) do
    GraphQL::Schema.from_definition(
      <<~GQL
        type Query {
          project(selector: ProjectSelectorInput!): Project
          projectsByType(type: ProjectType!): [Project!]!
          projectsByManyTypes(type: [ProjectType!]!): [Project!]!
          projects(filter: FilterInput): [Project!]!
          searchResult(query: String!): SearchResult
        }

        type Mutation {
          deleteProject(selector: ProjectSelectorInput!): DeleteProjectPayload!
        }

        input ProjectSelectorInput {
          organization: ID!
          project: ID!
        }

        input FilterInput {
          type: ProjectType
          pagination: PaginationInput
          order: [ProjectOrderByInput!]
        }

        input PaginationInput {
          limit: Int
          offset: Int
        }

        input ProjectOrderByInput {
          field: String!
          direction: OrderDirection
        }

        enum OrderDirection {
          ASC
          DESC
        }

        type ProjectSelector {
          organization: ID!
          project: ID!
        }

        type DeleteProjectPayload {
          selector: ProjectSelector!
          deletedProject: Project!
        }

        type Project {
          id: ID!
          cleanId: ID!
          name: String!
          type: ProjectType!
          buildUrl: String
          validationUrl: String
        }

        enum ProjectType {
          FEDERATION
          STITCHING
          SINGLE
          CUSTOM
        }

        union SearchResult = Project | ProjectSelector
      GQL
    )
  end

  let(:query_string) do
    %|
      mutation deleteProject($selector: ProjectSelectorInput!) {
        deleteProject(selector: $selector) {
          selector {
            organization
            project
          }

          deletedProject {
            id
            cleanId
            name
            type
          }
        }
      }
    |
  end

  it "collects used fields and arguments" do
    expect(used_fields).to include(
      "DeleteProjectPayload",
      "DeleteProjectPayload.selector",
      "Mutation",
      "Mutation.deleteProject",
      "Mutation.deleteProject.selector",
      "Project",
      "Project.cleanId",
      "Project.id",
      "Project.name",
      "Project.type",
      "ProjectSelector",
      "ProjectSelector.organization",
      "ProjectSelector.project"
    )
    expect(used_fields).not_to include(
      "Project.buildUrl",
      "Project.validationUrl"
    )
  end

  it "collects used input object fields" do
    expect(used_fields).to include(
      "ProjectSelectorInput",
      "ProjectSelectorInput.organization",
      "ProjectSelectorInput.project"
    )
  end

  context "with enum value in argument" do
    let(:query_string) do
      %|
      query getProjects($type: ProjectType!) {
        projectsByType(type: $type) {
          id
        }
      }
    |
    end

    it "collects all values of that enum type" do
      expect(used_fields).to include(
        "ProjectType.FEDERATION",
        "ProjectType.STITCHING",
        "ProjectType.SINGLE",
        "ProjectType.CUSTOM"
      )
    end
  end

  context "with enum value hardcoded into the query" do
    let(:query_string) do
      %|
      query getProjects {
        projectsByType(type: FEDERATION) {
          id
        }
      }
    |
    end

    it "collects used enumn values" do
      expect(used_fields).to include(
        "ProjectType.FEDERATION"
      )
      expect(used_fields).not_to include(
        "ProjectType.STITCHING",
        "ProjectType.SINGLE",
        "ProjectType.CUSTOM"
      )
    end
  end

  context "with only some input object fields used" do
    let(:query_string) do
      %|
      query getProjects($limit: Int!, $type: ProjectType!) {
        projects(filter: { pagination: { limit: $limit }, type: $type }) {
          id
        }
      }
    |
    end

    it "collects fields of specified input objects" do
      expect(used_fields).to include(
        "FilterInput",
        "FilterInput.pagination",
        "FilterInput.type",
        "PaginationInput",
        "PaginationInput.limit",
        "Query.projects.filter"
      )

      expect(used_fields).not_to include(
        "FilterInput.order",
        "PaginationInput.offset"
      )
    end
  end

  context "with query containining both input object variable as well as explicit input object fields" do
    let(:query_string) do
      %|
      query getProjects($type: ProjectType!, $pagination: PaginationInput) {
        projects(filter: { pagination: $pagination, type: $type }) {
          id
        }
      }
    |
    end

    it "collects all fields of input object variable, but only specific fields for the other input object type" do
      expect(used_fields).to include(
        "PaginationInput",
        "PaginationInput.limit",
        "PaginationInput.offset",
        "FilterInput.type",
        "FilterInput.pagination"
      )

      expect(used_fields).not_to include(
        "FilterInput.order"
      )
    end
  end

  context "with query containing list of input objects" do
    let(:query_string) do
      %|
      query getProjects($limit: Int!, $type: ProjectType!) {
        projects(filter: {
          pagination: {
            limit: $limit
          },
          type: $type,
          order: [
            {
              field: "id",
            }
          ]
        }) {
          id
        }
      }
      |
    end

    it "collects fields from the input values" do
      expect(used_fields).to include(
        "ProjectOrderByInput.field"
      )
      expect(used_fields).to_not include(
        "ProjectOrderByInput.direction"
      )
    end
  end

  context "with query containing enum value inside input object list" do
    let(:query_string) do
      %|
      query getProjects($limit: Int!, $type: ProjectType!) {
        projects(filter: {
          pagination: {
            limit: $limit
          },
          type: $type,
          order: [
            {
              field: "id",
              direction: ASC
            },
            {
              field: "cleanId",
            }
          ]
        }) {
          id
        }
      }
      |
    end

    it "collects the used enum values" do
      expect(used_fields).to include(
        "OrderDirection.ASC"
      )

      expect(used_fields).not_to include(
        "OrderDirection.DESC"
      )
    end
  end

  context "with query containing enum value in nested input object list" do
    let(:query_string) do
      %|
      query getProjects($type: ProjectType!, $limit: Int) {
        projects(filter: {
          pagination: {
            limit: $limit
          },
          type: $type,
          order: {
            field: "test",
            direction: ASC,
          }
        }) {
          id
        }
      }
    |
    end

    it "collects the enum value" do
      expect(used_fields).to include(
        "OrderDirection.ASC"
      )

      expect(used_fields).not_to include(
        "OrderDirection.DESC"
      )
    end
  end

  context "with query containing argument of enum values" do
    let(:query_string) do
      %|
      query getGatewayProjects {
        projectsByManyTypes(type: [STITCHING, FEDERATION])
      }
      |
    end

    it "collects the used enum values" do
      expect(used_fields).to include(
        "ProjectType.STITCHING",
        "ProjectType.FEDERATION"
      )

      expect(used_fields).not_to include(
        "ProjectType.SINGLE",
        "ProjectType.CUSTOM"
      )
    end
  end

  context "with a query containing a union type" do
    let(:query_string) do
      <<~GQL
        query searchProjects {
          searchResult(query: $query) {
            __typename
            ... on Project {
              id
            }
            ... on ProjectSelector {
              organization
            }
          }
        }
      GQL
    end

    it "collects all valid fields from union types" do
      expect(used_fields).to contain_exactly(
        "Query",
        "Query.searchResult",
        "Query.searchResult.query",
        "SearchResult",
        "SearchResult.__typename",
        "Project",
        "Project.id",
        "ProjectSelector",
        "ProjectSelector.organization",
        "String"
      )
    end
  end

  context "with process_variables enabled" do
    let(:process_variables) { true }

    context "when the variable is an input object with only some fields provided" do
      let(:query_string) do
        %|
          query getProjects($filter: FilterInput) {
            projects(filter: $filter) {
              id
            }
          }
        |
      end
      let(:variables) { {"filter" => {"type" => "FEDERATION", "pagination" => {"limit" => 10}}} }

      it "marks only the provided input fields, with `!` suffix for non-null values" do
        expect(used_fields).to include(
          "FilterInput.type",
          "FilterInput.type!",
          "FilterInput.pagination",
          "FilterInput.pagination!",
          "PaginationInput.limit",
          "PaginationInput.limit!",
          "ProjectType.FEDERATION"
        )
        expect(used_fields).not_to include(
          "FilterInput.order",
          "FilterInput.order!",
          "PaginationInput.offset",
          "PaginationInput.offset!"
        )
      end
    end

    context "when the variable is a list of input objects" do
      let(:query_string) do
        %|
          query getProjects($filter: FilterInput) {
            projects(filter: $filter) {
              id
            }
          }
        |
      end
      let(:variables) { {"filter" => {"order" => [{"field" => "id", "direction" => "ASC"}, {"field" => "name"}]}} }

      it "walks each list item and unions the provided fields" do
        expect(used_fields).to include(
          "FilterInput.order",
          "FilterInput.order!",
          "ProjectOrderByInput.field",
          "ProjectOrderByInput.field!",
          "ProjectOrderByInput.direction",
          "ProjectOrderByInput.direction!",
          "OrderDirection.ASC"
        )
        expect(used_fields).not_to include(
          "OrderDirection.DESC"
        )
      end
    end

    context "when the variable is an enum" do
      let(:query_string) do
        %|
          query getProjects($type: ProjectType!) {
            projectsByType(type: $type) {
              id
            }
          }
        |
      end
      let(:variables) { {"type" => "STITCHING"} }

      it "marks only the provided enum value" do
        expect(used_fields).to include(
          "ProjectType.STITCHING"
        )
        expect(used_fields).not_to include(
          "ProjectType.FEDERATION",
          "ProjectType.SINGLE",
          "ProjectType.CUSTOM"
        )
      end
    end

    context "when the variable is a list of enums" do
      let(:query_string) do
        %|
          query getProjects($types: [ProjectType!]!) {
            projectsByManyTypes(type: $types)
          }
        |
      end
      let(:variables) { {"types" => ["FEDERATION", "STITCHING"]} }

      it "marks only the provided enum values" do
        expect(used_fields).to include(
          "ProjectType.FEDERATION",
          "ProjectType.STITCHING"
        )
        expect(used_fields).not_to include(
          "ProjectType.SINGLE",
          "ProjectType.CUSTOM"
        )
      end
    end

    context "when the variable is omitted or null" do
      let(:query_string) do
        %|
          query getProjects($filter: FilterInput) {
            projects(filter: $filter) {
              id
            }
          }
        |
      end
      let(:variables) { {} }

      it "marks nothing beyond the argument coordinate itself" do
        expect(used_fields).to include(
          "Query.projects.filter",
          "FilterInput"
        )
        expect(used_fields).not_to include(
          "FilterInput.type",
          "FilterInput.pagination",
          "FilterInput.order"
        )
      end
    end

    context "when a nullable input field is explicitly null" do
      let(:query_string) do
        %|
          query getProjects($filter: FilterInput) {
            projects(filter: $filter) {
              id
            }
          }
        |
      end
      let(:variables) { {"filter" => {"type" => nil, "pagination" => {"limit" => 5}}} }

      it "marks the field as touched but without the `!` suffix" do
        expect(used_fields).to include(
          "FilterInput.type",
          "FilterInput.pagination",
          "FilterInput.pagination!",
          "PaginationInput.limit",
          "PaginationInput.limit!"
        )
        expect(used_fields).not_to include(
          "FilterInput.type!"
        )
      end
    end
  end

  context "with process_variables disabled (default)" do
    let(:query_string) do
      %|
        query getProjects($filter: FilterInput) {
          projects(filter: $filter) {
            id
          }
        }
      |
    end
    let(:variables) { {"filter" => {"type" => "FEDERATION"}} }

    it "marks every possible input field regardless of what the variable actually contains" do
      expect(used_fields).to include(
        "FilterInput.type",
        "FilterInput.pagination",
        "FilterInput.order"
      )
      expect(used_fields).not_to include(
        "FilterInput.type!",
        "FilterInput.pagination!"
      )
    end
  end

  context "with an invalid field" do
    let(:query_string) do
      <<~GQL
        query getGatewayProjects {
          searchResult(query: $query) {
            nonExistentField {
              subField
            }
            ... on Project {
              id
            }
          }
          nonExistentField {
            subField
          }
        }
      GQL
    end

    it "collects all valid fields and excludes invalid fields" do
      expect(used_fields).to contain_exactly(
        "Query",
        "Query.searchResult",
        "Query.searchResult.query",
        "SearchResult",
        "SearchResult.nonExistentField",
        "Project",
        "Project.id",
        "Query.nonExistentField",
        "String"
      )
    end
  end
end
