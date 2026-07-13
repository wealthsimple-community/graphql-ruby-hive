# frozen_string_literal: true

require "net/http"
require "uri"

module GraphQL
  class Hive < GraphQL::Tracing::PlatformTracing
    # API client
    class Client
      def initialize(options)
        @options = options
      end

      def send(path, body, _log_type)
        path = path.to_s
        if path == "/usage" && @options[:target] && @options[:target] != ""
          path = "/usage/#{@options[:target]}"
        end

        scheme = (@options[:port].to_s == "443") ? "https" : "http"
        endpoint = @options[:endpoint] || "app.graphql-hive.com"
        uri = URI::HTTP.build(
          scheme: scheme,
          host: endpoint,
          port: @options[:port] || "443",
          path: path
        )
        http = setup_http(uri)
        request = build_request(uri, body)

        log_request(request, scheme, endpoint, path)

        response = http.request(request)

        code = response.code.to_i
        if code >= 400 && code < 500
          error_message = "Unsuccessful response: #{response.code} - #{response.message}"
          log_error("#{error_message} #{extract_error_details(response)}")
        end

        @options[:logger].debug(response.inspect)
        @options[:logger].debug(response.body.inspect)
      rescue => e
        log_error("Failed to send data: #{e}")
      end

      def setup_http(uri)
        http = ::Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = @options[:port].to_s == "443"
        http.read_timeout = 2
        http
      end

      def build_request(uri, body)
        request = Net::HTTP::Post.new(uri.request_uri)
        request["Authorization"] = "Bearer #{@options[:token]}"
        request["X-Usage-API-Version"] = "2"
        request["content-type"] = "application/json"
        request["User-Agent"] = "Hive@#{Graphql::Hive::VERSION}"
        request["graphql-client-name"] = "Hive Ruby Client"
        request["graphql-client-version"] = Graphql::Hive::VERSION
        request["X-Request-Id"] = SecureRandom.uuid
        request.body = JSON.generate(body)
        request
      end

      def log_request(request, scheme, endpoint, path)
        log_message = "#{request.method} #{scheme}://#{endpoint}#{path} request id: #{request["X-Request-Id"]}"

        if @options[:log_request_details]
          @options[:logger].info(log_message)
        else
          @options[:logger].debug(log_message)
        end
      end

      def extract_error_details(response)
        parsed_body = JSON.parse(response.body)
        return unless parsed_body.is_a?(Hash) && parsed_body["errors"].is_a?(Array)
        parsed_body["errors"].map { |error| "{ path: #{error["path"]}, message: #{error["message"]} }" }.join(", ")
      rescue JSON::ParserError
        "Could not parse response from Hive"
      end

      def log_error(message)
        if @options[:warn_on_hive_errors]
          @options[:logger].warn(message)
        else
          @options[:logger].error(message)
        end
      end
    end
  end
end
