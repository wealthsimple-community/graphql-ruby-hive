# frozen_string_literal: true

require "spec_helper"
require "graphql-hive"

RSpec.describe GraphQL::Hive::Client do
  let(:options) do
    {
      endpoint: "app.graphql-hive.com",
      port: 443,
      token: "test-token",
      logger: Logger.new(nil)
    }
  end

  let(:client) { described_class.new(options) }
  let(:body) { {size: 3, map: {}, operations: []} }

  describe "#initialize" do
    it "sets the instance" do
      expect(client.instance_variable_get(:@options)).to eq(options)
    end
  end

  describe "#send" do
    let(:uuid_regex) { /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/ }

    before do
      stub_request(:post, "https://app.graphql-hive.com/usage")
        .to_return(status: 200, body: "", headers: {})
    end

    it "sets up the HTTP session" do
      client.send(:"/usage", body, :usage)
    end

    it "creates the request with the correct headers and body" do
      client.send(:"/usage", body, :usage)

      # Verify the request was made with correct headers
      expect(WebMock).to have_requested(:post, "https://app.graphql-hive.com/usage")
        .with(
          headers: {
            "Authorization" => "Bearer test-token",
            "X-Usage-API-Version" => "2",
            "Content-Type" => "application/json",
            "User-Agent" => "Hive@#{Graphql::Hive::VERSION}",
            "Graphql-Client-Name" => "Hive Ruby Client",
            "Graphql-Client-Version" => Graphql::Hive::VERSION
          }
        )
        .with { |req| req.headers["X-Request-Id"].match?(uuid_regex) }
    end

    it "executes the request" do
      client.send(:"/usage", body, :usage)

      # Verify the request was actually made
      expect(WebMock).to have_requested(:post, "https://app.graphql-hive.com/usage")
    end

    it "always includes X-Request-Id header with valid UUID format" do
      client.send(:"/usage", body, :usage)

      # Verify X-Request-Id header is set with a valid UUID format
      expect(WebMock).to have_requested(:post, "https://app.graphql-hive.com/usage")
        .with { |req| req.headers["X-Request-Id"].match?(uuid_regex) }
    end

    context "when target is provided in options" do
      let(:options_with_target) do
        options.merge(target: "my-org/my-project/production")
      end
      let(:client_with_target) { described_class.new(options_with_target) }

      before do
        stub_request(:post, "https://app.graphql-hive.com/usage/my-org/my-project/production")
          .to_return(status: 200, body: "", headers: {})
        stub_request(:post, "https://app.graphql-hive.com/registry")
          .to_return(status: 200, body: "", headers: {})
      end

      it "modifies the usage path to include the target" do
        client_with_target.send(:"/usage", body, :usage)

        expect(WebMock).to have_requested(:post, "https://app.graphql-hive.com/usage/my-org/my-project/production")
      end

      it "does not modify non-usage paths" do
        client_with_target.send(:"/registry", body, :registry)

        expect(WebMock).to have_requested(:post, "https://app.graphql-hive.com/registry")
      end

      it "includes X-Request-Id header for registry requests" do
        client_with_target.send(:"/registry", body, :registry)

        expect(WebMock).to have_requested(:post, "https://app.graphql-hive.com/registry")
          .with { |req| req.headers["X-Request-Id"].match?(uuid_regex) }
      end
    end

    context "when target is not provided in options" do
      it "uses the original path unchanged" do
        client.send(:"/usage", body, :usage)

        expect(WebMock).to have_requested(:post, "https://app.graphql-hive.com/usage")
      end
    end

    it "logs an error when an exception is raised" do
      stub_request(:post, "https://app.graphql-hive.com/usage")
        .to_raise(StandardError.new("Network error"))

      expect(options[:logger]).to receive(:error).with("Failed to send data: Network error")

      expect { client.send(:"/usage", body, :usage) }.not_to raise_error
    end

    context "when warn_on_hive_errors is true" do
      let(:options) do
        {
          endpoint: "app.graphql-hive.com",
          port: 443,
          token: "test-token",
          logger: Logger.new(nil),
          warn_on_hive_errors: true
        }
      end

      it "logs a warning when an exception is raised" do
        stub_request(:post, "https://app.graphql-hive.com/usage")
          .to_raise(StandardError.new("Network error"))

        expect(options[:logger]).to receive(:warn).with("Failed to send data: Network error")

        expect { client.send(:"/usage", body, :usage) }.not_to raise_error
      end
    end

    context "when the response status code is between 400 and 499" do
      before do
        stub_request(:post, "https://app.graphql-hive.com/usage")
          .to_return(
            status: [400, "Bad Request"],
            body: '{"errors":[{"path":"test1","message":"Error message 1"},{"path":"test2","message":"Error message 2"}]}',
            headers: {}
          )
      end

      it "logs an error with error details by default" do
        expect(options[:logger]).to receive(:error).with("Unsuccessful response: 400 - Bad Request { path: test1, message: Error message 1 }, { path: test2, message: Error message 2 }")
        client.send(:"/usage", body, :usage)
      end

      context "when warn_on_hive_errors is true" do
        let(:options) do
          {
            endpoint: "app.graphql-hive.com",
            port: 443,
            token: "test-token",
            logger: Logger.new(nil),
            warn_on_hive_errors: true
          }
        end

        it "logs a warning with error details" do
          expect(options[:logger]).to receive(:warn).with("Unsuccessful response: 400 - Bad Request { path: test1, message: Error message 1 }, { path: test2, message: Error message 2 }")
          client.send(:"/usage", body, :usage)
        end
      end

      context "when the response body is not valid JSON" do
        before do
          stub_request(:post, "https://app.graphql-hive.com/usage")
            .to_return(
              status: [400, "Bad Request"],
              body: "Invalid JSON",
              headers: {}
            )
        end

        it "logs an error without error details" do
          expect(options[:logger]).to receive(:error).with("Unsuccessful response: 400 - Bad Request Could not parse response from Hive")
          client.send(:"/usage", body, :usage)
        end
      end

      context "when the response body does not contain errors" do
        before do
          stub_request(:post, "https://app.graphql-hive.com/usage")
            .to_return(
              status: [401, "Unauthorized"],
              body: "{}",
              headers: {}
            )
        end

        it "logs an error without error details" do
          expect(options[:logger]).to receive(:error).with("Unsuccessful response: 401 - Unauthorized ")
          client.send(:"/usage", body, :usage)
        end
      end
    end

    context "with different endpoint and port configurations" do
      let(:http_options) do
        {
          endpoint: "custom.hive.com",
          port: 8080,
          token: "test-token",
          logger: Logger.new(nil)
        }
      end
      let(:http_client) { described_class.new(http_options) }

      before do
        stub_request(:post, "http://custom.hive.com:8080/usage")
          .to_return(status: 200, body: "", headers: {})
      end

      it "logs with HTTP scheme when port is not 443" do
        http_client.send(:"/usage", body, :usage)

        expect(WebMock).to have_requested(:post, "http://custom.hive.com:8080/usage")
      end
    end

    context "logging" do
      let(:usage_log_regex) { /POST https:\/\/app\.graphql-hive\.com\/usage request id: #{uuid_regex}/ }
      let(:registry_log_regex) { /POST https:\/\/app\.graphql-hive\.com\/registry request id: #{uuid_regex}/ }

      context "when log_request_details is true" do
        let(:info_options) do
          {
            endpoint: "app.graphql-hive.com",
            port: 443,
            token: "test-token",
            logger: Logger.new(nil),
            log_request_details: true
          }
        end
        let(:info_client) { described_class.new(info_options) }

        before do
          stub_request(:post, "https://app.graphql-hive.com/usage")
            .to_return(status: 200, body: "", headers: {})
        end

        it "logs request details at info level" do
          expect(info_options[:logger]).to receive(:info).with(usage_log_regex)

          info_client.send(:"/usage", body, :usage)
        end

        it "logs registry request details at info level" do
          stub_request(:post, "https://app.graphql-hive.com/registry")
            .to_return(status: 200, body: "", headers: {})

          expect(info_options[:logger]).to receive(:info).with(registry_log_regex)

          info_client.send(:"/registry", body, :registry)
        end

        context "with custom endpoint" do
          let(:custom_endpoint_options) do
            {
              endpoint: "custom.hive.com",
              port: 443,
              token: "test-token",
              logger: Logger.new(nil),
              log_request_details: true
            }
          end
          let(:custom_endpoint_client) { described_class.new(custom_endpoint_options) }

          before do
            stub_request(:post, "https://custom.hive.com/usage")
              .to_return(status: 200, body: "", headers: {})
          end

          it "logs request details with custom endpoint at info level" do
            expect(custom_endpoint_options[:logger]).to receive(:info).with(/POST https:\/\/custom\.hive\.com\/usage request id: #{uuid_regex}/)

            custom_endpoint_client.send(:"/usage", body, :usage)
          end
        end

        context "with custom scheme (non-443 port)" do
          let(:custom_scheme_options) do
            {
              endpoint: "app.graphql-hive.com",
              port: 8080,
              token: "test-token",
              logger: Logger.new(nil),
              log_request_details: true
            }
          end
          let(:custom_scheme_client) { described_class.new(custom_scheme_options) }

          before do
            stub_request(:post, "http://app.graphql-hive.com:8080/usage")
              .to_return(status: 200, body: "", headers: {})
          end

          it "logs request details with HTTP scheme at info level" do
            expect(custom_scheme_options[:logger]).to receive(:info).with(/POST http:\/\/app\.graphql-hive\.com\/usage request id: #{uuid_regex}/)

            custom_scheme_client.send(:"/usage", body, :usage)
          end
        end
      end

      context "when log_request_details is false (default)" do
        before do
          stub_request(:post, "https://app.graphql-hive.com/usage")
            .to_return(status: 200, body: '{"success": true}', headers: {})
        end

        it "logs request details, response object, and response body at debug level" do
          expect(options[:logger]).to receive(:debug).with(usage_log_regex)
          expect(options[:logger]).to receive(:debug).with("#<Net::HTTPOK 200  readbody=true>")
          expect(options[:logger]).to receive(:debug).with('"{\\"success\\": true}"')

          client.send(:"/usage", body, :usage)
        end

        it "logs registry request details at debug level" do
          stub_request(:post, "https://app.graphql-hive.com/registry")
            .to_return(status: 200, body: '{"schema": "published"}', headers: {})

          expect(options[:logger]).to receive(:debug).with(registry_log_regex)
          expect(options[:logger]).to receive(:debug).with("#<Net::HTTPOK 200  readbody=true>")
          expect(options[:logger]).to receive(:debug).with('"{\\"schema\\": \\"published\\"}"')

          client.send(:"/registry", body, :registry)
        end
      end
    end
  end
end
