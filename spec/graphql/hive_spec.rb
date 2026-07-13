# frozen_string_literal: true

require "spec_helper"
require "graphql-hive"

RSpec.describe Graphql::Hive do
  it "has a version number" do
    expect(Graphql::Hive::VERSION).not_to be nil
  end
end

TestQuery1 = Class.new(GraphQL::Schema::Object) do
  field :hello, String
end

TestSchema1 = Class.new(GraphQL::Schema) do
  query TestQuery1
end

TestQuery2 = Class.new(GraphQL::Schema::Object) do
  field :hello, String
end

TestSchema2 = Class.new(GraphQL::Schema) do
  query TestQuery2
end

RSpec.describe GraphQL::Hive do
  let(:logger) { instance_double(Logger) }

  before do
    allow(Logger).to receive(:new).and_return(logger)
    allow(logger).to receive(:formatter=)
    allow(logger).to receive(:level=)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info!)
  end

  describe "organization-level token validation" do
    context "when token starts with hvo1/ and target is provided" do
      let(:options) do
        {
          token: "hvo1/test-org-token",
          target: "my-org/my-project/production",
          enabled: true,
          report_schema: false,
          collect_usage_sampling: {sample_rate: 1.0}
        }
      end

      it "does not disable the plugin" do
        hive_instance = GraphQL::Hive.new(options)
        expect(hive_instance.instance_variable_get(:@options)[:enabled]).to be_truthy
      end

      it "does not log a warning" do
        GraphQL::Hive.new(options)
        expect(logger).not_to have_received(:warn)
      end
    end

    context "when token starts with hvo1/ but target is missing" do
      let(:options) do
        {
          token: "hvo1/test-org-token",
          enabled: true
        }
      end

      it "disables the plugin" do
        hive_instance = GraphQL::Hive.new(options)
        expect(hive_instance.instance_variable_get(:@options)[:enabled]).to be_falsey
      end

      it "logs a warning about missing target" do
        expect(logger).to receive(:warn).with("Organization-level token detected but `target` option is missing. Target must be specified for organization-level tokens.")
        GraphQL::Hive.new(options)
      end
    end

    context "when token starts with hvo1/ and target is nil" do
      let(:options) do
        {
          token: "hvo1/test-org-token",
          target: nil,
          enabled: true
        }
      end

      it "disables the plugin" do
        hive_instance = GraphQL::Hive.new(options)
        expect(hive_instance.instance_variable_get(:@options)[:enabled]).to be_falsey
      end

      it "logs a warning about missing target" do
        expect(logger).to receive(:warn).with("Organization-level token detected but `target` option is missing. Target must be specified for organization-level tokens.")
        GraphQL::Hive.new(options)
      end
    end

    context "when token starts with hvo1/ and target is empty string" do
      let(:options) do
        {
          token: "hvo1/test-org-token",
          target: "",
          enabled: true
        }
      end

      it "disables the plugin" do
        hive_instance = GraphQL::Hive.new(options)
        expect(hive_instance.instance_variable_get(:@options)[:enabled]).to be_falsey
      end

      it "logs a warning about missing target" do
        expect(logger).to receive(:warn).with("Organization-level token detected but `target` option is missing. Target must be specified for organization-level tokens.")
        GraphQL::Hive.new(options)
      end
    end

    context "when token does not start with hvo1/" do
      let(:options) do
        {
          token: "regular-token",
          enabled: true,
          report_schema: false,
          collect_usage_sampling: {sample_rate: 1.0}
        }
      end

      it "does not require target parameter" do
        hive_instance = GraphQL::Hive.new(options)
        expect(hive_instance.instance_variable_get(:@options)[:enabled]).to be_truthy
      end

      it "does not log a warning" do
        GraphQL::Hive.new(options)
        expect(logger).not_to have_received(:warn)
      end
    end

    context "when token is nil" do
      let(:options) do
        {
          enabled: true
        }
      end

      it "disables the plugin and logs missing token warning" do
        expect(logger).to receive(:warn).with("`token` options is missing")
        hive_instance = GraphQL::Hive.new(options)
        expect(hive_instance.instance_variable_get(:@options)[:enabled]).to be_falsey
      end
    end
  end

  describe "schema publishing" do
    let(:mock_client) { instance_double(GraphQL::Hive::Client) }

    before do
      allow(GraphQL::Hive::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:send)
    end

    context "without target (traditional tokens)" do
      let(:test_schema1) { TestSchema1 }

      let(:options) do
        {
          token: "traditional-token",
          report_schema: true,
          reporting: {
            author: "test-author",
            commit: "abc123",
            service_name: "test-service",
            service_url: "http://localhost:4000/graphql"
          }
        }
      end

      it "sends schema publish without target in mutation variables" do
        GraphQL::Hive.use(test_schema1)
        GraphQL::Hive.new(options)

        expected_body = {
          query: GraphQL::Hive::REPORT_SCHEMA_MUTATION,
          operationName: "schemaPublish",
          variables: {
            input: {
              sdl: be_a(String),
              author: "test-author",
              commit: "abc123",
              service: "test-service",
              url: "http://localhost:4000/graphql",
              force: true
            }
          }
        }

        expect(mock_client).to have_received(:send).with(:"/registry", expected_body, :"report-schema")
      end
    end

    context "with target (organization-level tokens)" do
      let(:test_schema2) { TestSchema2 }

      let(:options) do
        {
          token: "hvo1/org-token",
          target: "my-org/my-project/production",
          report_schema: true,
          reporting: {
            author: "test-author",
            commit: "abc123",
            service_name: "test-service",
            service_url: "http://localhost:4000/graphql"
          }
        }
      end

      it "sends schema publish with target in mutation variables" do
        GraphQL::Hive.use(test_schema2)
        GraphQL::Hive.new(options)

        expected_body = {
          query: GraphQL::Hive::REPORT_SCHEMA_MUTATION,
          operationName: "schemaPublish",
          variables: {
            input: {
              sdl: be_a(String),
              author: "test-author",
              commit: "abc123",
              service: "test-service",
              url: "http://localhost:4000/graphql",
              target: "my-org/my-project/production",
              force: true
            }
          }
        }

        expect(mock_client).to have_received(:send).with(:"/registry", expected_body, :"report-schema")
      end
    end
  end
end
