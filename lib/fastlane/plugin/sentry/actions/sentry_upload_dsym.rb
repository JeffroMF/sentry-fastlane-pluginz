module Fastlane
  module Actions
    class SentryUploadDsymAction < Action
      def self.run(params)
        Helper::SentryHelper.check_sentry_cli!

        # Params - API
        url = params[:url]
        auth_token = params[:auth_token]
        api_key = params[:api_key]
        org = params[:org_slug]
        project = params[:project_slug]

        # Params - dSYM
        dsym_path = params[:dsym_path]
        dsym_paths = params[:dsym_paths] || []

        has_api_key = !api_key.to_s.empty?
        has_auth_token = !auth_token.to_s.empty?

        # Will fail if none or both authentication methods are provided
        if !has_api_key && !has_auth_token
          UI.user_error!("No API key or authentication token found for SentryAction given, pass using `api_key: 'key'` or `auth_token: 'token'`")
        elsif has_api_key && has_auth_token
          UI.user_error!("Both API key and authentication token found for SentryAction given, please only give one")
        elsif has_api_key && !has_auth_token
          UI.deprecated("Please consider switching to auth_token ... api_key will be removed in the future")
        end

        ENV['SENTRY_API_KEY'] = api_key unless api_key.to_s.empty?
        ENV['SENTRY_AUTH_TOKEN'] = auth_token unless auth_token.to_s.empty?
        ENV['SENTRY_URL'] = url unless url.to_s.empty?
        ENV['SENTRY_LOG_LEVEL'] = 'debug' if FastlaneCore::Globals.verbose?

        # Verify dsym(s)
        dsym_paths += [dsym_path] unless dsym_path.nil?
        dsym_paths = dsym_paths.map { |path| File.absolute_path(path) }
        dsym_paths.each do |path|
          UI.user_error!("dSYM does not exist at path: #{path}") unless File.exist? path
        end

        UI.success("sentry-cli #{Fastlane::Sentry::CLI_VERSION} installed!")
        call_sentry_cli(dsym_paths, org, project)
        UI.success("Successfully uploaded dSYMs!")
      end

      def self.call_sentry_cli(dsym_paths, org, project)
        UI.message "Starting sentry-cli..."
        require 'open3'
        require 'shellwords'
        org = Shellwords.escape(org)
        project = Shellwords.escape(project)
        error = []
        command = "sentry-cli upload-dsym '#{dsym_paths.join("','")}' --org #{org} --project #{project}"
        if FastlaneCore::Globals.verbose?
          UI.verbose("sentry-cli command:\n\n")
          UI.command(command.to_s)
          UI.verbose("\n\n")
        end
        Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
          while (line = stderr.gets)
            error << line.strip!
          end
          while (line = stdout.gets)
            UI.message(line.strip!)
          end
          exit_status = wait_thr.value
          unless exit_status.success? && error.empty?
            handle_error(error)
          end
        end
      end

      def self.handle_error(errors)
        fatal = false
        for error in errors do
          if error
            if error =~ /error/
              UI.error(error.to_s)
              fatal = true
            else
              UI.verbose(error.to_s)
            end
          end
        end
        UI.user_error!('Error while trying to upload dSYM to Sentry') if fatal
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Upload dSYM symbolication files to Sentry"
      end

      def self.details
        [
          "This action allows you to upload symbolication files to Sentry.",
          "It's extra useful if you use it to download the latest dSYM files from Apple when you",
          "use Bitcode"
        ].join(" ")
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :url,
                                       env_name: "SENTRY_URL",
                                       description: "Url for Sentry",
                                       is_string: true,
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :auth_token,
                                       env_name: "SENTRY_AUTH_TOKEN",
                                       description: "Authentication token for Sentry",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :api_key,
                                       env_name: "SENTRY_API_KEY",
                                       description: "API key for Sentry",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :org_slug,
                                       env_name: "SENTRY_ORG_SLUG",
                                       description: "Organization slug for Sentry project",
                                       verify_block: proc do |value|
                                         UI.user_error!("No organization slug for SentryAction given, pass using `org_slug: 'org'`") unless value and !value.empty?
                                       end),
          FastlaneCore::ConfigItem.new(key: :project_slug,
                                       env_name: "SENTRY_PROJECT_SLUG",
                                       description: "Project slug for Sentry",
                                       verify_block: proc do |value|
                                         UI.user_error!("No project slug for SentryAction given, pass using `project_slug: 'project'`") unless value and !value.empty?
                                       end),
          FastlaneCore::ConfigItem.new(key: :dsym_path,
                                       env_name: "SENTRY_DSYM_PATH",
                                       description: "Path to your symbols file. For iOS and Mac provide path to app.dSYM.zip",
                                       default_value: Actions.lane_context[SharedValues::DSYM_OUTPUT_PATH],
                                       optional: true,
                                       verify_block: proc do |value|
                                         # validation is done in the action
                                       end),
          FastlaneCore::ConfigItem.new(key: :dsym_paths,
                                       env_name: "SENTRY_DSYM_PATHS",
                                       description: "Path to an array of your symbols file. For iOS and Mac provide path to app.dSYM.zip",
                                       default_value: Actions.lane_context[SharedValues::DSYM_PATHS],
                                       is_string: false,
                                       optional: true,
                                       verify_block: proc do |value|
                                         # validation is done in the action
                                       end)

        ]
      end

      def self.return_value
        nil
      end

      def self.authors
        ["joshdholtz"]
      end

      def self.is_supported?(platform)
        platform == :ios
      end
    end
  end
end
