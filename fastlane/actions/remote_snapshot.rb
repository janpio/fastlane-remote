module Fastlane
  module Actions
    module SharedValues
      REMOTE_SCAN_CUSTOM_VALUE = :REMOTE_SCAN_CUSTOM_VALUE
    end

    class RemoteSnapshotAction < Action

      APP_PATH = 'iosapp_with_snapshot' # TODO extract from options[:project]   
      CI_PROVIDER = 'azure' # TODO Extract this ci_provider stuff into the server
      ACTION = 'snapshot'

      def self.run(params)
        app_upload_id        = self.upload_app(APP_PATH)
        remote_id            = self.trigger_remote_action(CI_PROVIDER, ACTION, app_upload_id)
        log                  = self.wait_and_retrieve_log(CI_PROVIDER, remote_id)
        screenshot_upload_id = self.output_log(CI_PROVIDER, log, ACTION)
        self.download_screenshots(screenshot_upload_id)
      
        # Actions.lane_context[SharedValues::REMOTE_SCAN_CUSTOM_VALUE] = "my_val"
      end

      def self.upload_app(app_path)
        zip_content_path = "#{app_path}/.." # TODO param
        
        # archive app
        checksum = Zlib::crc32(Dir.glob("#{zip_content_path}/**/*[^zip]").map { |name| [name, File.mtime(name)] }.to_s)
        archive = "#{checksum}.zip"
        if(!File.exist?(archive))
          spinner = TTY::Spinner.new("[:spinner] Zipping app...", format: :dots)
          spinner.auto_spin
          zf = ZipFileGenerator.new(zip_content_path, archive)
          zf.write()
          spinner.success("Done: #{archive}")
        else
          puts "Archive already exists."
        end
        
        # upload archive
        spinner = TTY::Spinner.new("[:spinner] Uploading archive...", format: :dots)
        spinner.auto_spin
        upload_id = upload_file(archive)
        # TODO skip additional upload if file was uploaded before (assumption: if archive already existed, it was also uploaded: check via new API if true)
        spinner.success("Done (upload_id = #{upload_id})")
        upload_id
      end
    
      def self.upload_file(filename)
        require 'net/http/post/multipart'
    
        url = URI.parse('http://remote-fastlane.betamo.de/upload.php')
        File.open(filename) do |file|
          req = Net::HTTP::Post::Multipart.new url.path,
            "datei" => UploadIO.new(file, "application/zip", filename)
          res = Net::HTTP.start(url.host, url.port) do |http|
            # TODO handle eventual upload errors
            return http.request(req).body
          end
        end
      end
    
      def self.trigger_remote_action(ci_provider, action, upload_id)
        spinner = TTY::Spinner.new("[:spinner] Triggering remote action...", format: :dots)
        spinner.auto_spin
        url = "http://remote-fastlane.betamo.de/trigger_build.php?upload_id=#{upload_id}&action=#{action}&ci_provider=#{ci_provider}"
        if ENV['repo'] && ENV['branch']
          url = url + "&repo=#{ENV['repo']}&branch=#{ENV['branch']}"
        end
        created_request = other_action.download(url: url)
        # TODO handle eventual errors

        # TODO trigger_build.php should just return the ID, nothing else - making this code obsolete
        if ci_provider == 'travis'
          id = created_request['request']['id']
        elsif ci_provider == 'azure'
          id = created_request['id'] 
        end

        spinner.success("Running (remote id = #{id})")

        return id
      end
    
      def self.wait_and_retrieve_log(ci_provider, remote_id)
        spinner = TTY::Spinner.new("[:spinner] Waiting for remote action to finish...", format: :dots)
        spinner.auto_spin
        loop do
          url = "http://remote-fastlane.betamo.de/retrieve_log.php?ci_provider=#{ci_provider}&id=#{remote_id}"           
          response = other_action.download(url: url)
          if response != 'Still processing' # TODO check for HTTP code here
            spinner.success("Done.")
            return response
          end
          sleep(3)
        end
      end
    
      def self.output_log(ci_provider, log, action)    
        # extract screenshot_upload_id
        match = log.match(/<UPLOAD_ID>(.*)<\/UPLOAD_ID/m)
        if match
          screenshot_upload_id = match[1]
        end

        # extract relevant action log
        # TODO maybe better do on server side?
        relevant_log = ''
        keep = false
        start_line = /Cruising over to lane 'screenshot'/ # TODO
        end_line = /Cruising back to lane 'remote_snapshot'/ # TODO
        log.each_line do |line|
          keep = false if line =~ end_line
          relevant_log = relevant_log + line if keep == true
          keep = true if line =~ start_line
        end
        # TODO remove other CI specific stuff (maybe better on server side?)
        puts relevant_log

        return screenshot_upload_id
      end

      def self.download_screenshots(screenshot_upload_id)
        spinner = TTY::Spinner.new("[:spinner] Downloading and unzipping screenshots...", format: :dots)
        spinner.auto_spin
        other_action.download_file(
          url: "http://remote-fastlane.betamo.de/uploads/#{screenshot_upload_id}", 
          destination_path: './tmp/archive.zip'
        )
        other_action.unzip(
          file: "./tmp/archive.zip", 
          destination_path: "./screenshots"
        )
        spinner.success("Done.")

        export_path = "./fastlane/screenshots/screenshots.html"
        UI.success("Successfully created HTML file with an overview of all the screenshots: '#{export_path}'")
        #system("open '#{export_path}'") unless Snapshot.config[:skip_open_summary] # TODO
      end
      
      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "A short description with <= 80 characters of what this action does"
      end

      def self.details
        # Optional:
        # this is your chance to provide a more detailed description of this action
        "You can use this action to do cool things..."
      end

      def self.available_options
        # Define all options your action supports. 
        
        # Below a few examples
        [
          FastlaneCore::ConfigItem.new(key: :project, # TODO
                                       env_name: "FL_REMOTE_SCAN_API_TOKEN", # The name of the environment variable
                                       description: "API Token for RemoteScanAction", # a short description of this parameter
                                       verify_block: proc do |value|
                                          UI.user_error!("No API token for RemoteScanAction given, pass using `api_token: 'token'`") unless (value and not value.empty?)
                                          # UI.user_error!("Couldn't find file at path '#{value}'") unless File.exist?(value)
                                       end),
          FastlaneCore::ConfigItem.new(key: :devices, # TODO
                                       env_name: "FL_REMOTE_SCAN_DEVELOPMENT",
                                       description: "Create a development certificate instead of a distribution one",
                                       is_string: false, # true: verifies the input is a string, false: every kind of value
                                       default_value: false), # the default value if the user didn't provide one
          FastlaneCore::ConfigItem.new(key: :languages, # TODO
                                       env_name: "FL_REMOTE_SCAN_DEVELOPMENT",
                                       description: "Create a development certificate instead of a distribution one",
                                       is_string: false, # true: verifies the input is a string, false: every kind of value
                                       default_value: false) # the default value if the user didn't provide one
          # TODO other scan params
        ]
      end

      def self.output
        # Define the shared values you are going to provide
        # Example
        [
          ['REMOTE_SCAN_CUSTOM_VALUE', 'A description of what this value contains']
        ]
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.authors
        # So no one will ever forget your contribution to fastlane :) You are awesome btw!
        ["Your GitHub/Twitter Name"]
      end

      def self.is_supported?(platform)
        # you can do things like
        # 
        #  true
        # 
        #  platform == :ios
        # 
        #  [:ios, :mac].include?(platform)
        # 

        platform == :ios
      end
    end
  end
end

require 'zip'

# This is a simple example which uses rubyzip to
# recursively generate a zip file from the contents of
# a specified directory. The directory itself is not
# included in the archive, rather just its contents.
#
# Usage:
#   directoryToZip = "/tmp/input"
#   outputFile = "/tmp/out.zip"
#   zf = ZipFileGenerator.new(directoryToZip, outputFile)
#   zf.write()
class ZipFileGenerator

# Initialize with the directory to zip and the location of the output archive.
def initialize(inputDir, outputFile)
  @inputDir = inputDir
  @outputFile = outputFile
end

# Zip the input directory.
def write()
  #entries = Dir.entries(@inputDir); entries.delete("."); entries.delete("..")
  entries = Dir.entries(@inputDir).reject { |f| f =~ /\.$|\.git|\.zip/ } # via https://stackoverflow.com/a/12342439/252627
  io = Zip::File.open(@outputFile, Zip::File::CREATE);

  writeEntries(entries, "", io)
  io.close();
end

# A helper method to make the recursion work.
private
def writeEntries(entries, path, io)
  entries.each { |e|
    zipFilePath = path == "" ? e : File.join(path, e)
    diskFilePath = File.join(@inputDir, zipFilePath)
    #puts "Deflating " + diskFilePath
    if  File.directory?(diskFilePath)
      io.mkdir(zipFilePath)
      subdir =Dir.entries(diskFilePath); subdir.delete("."); subdir.delete("..")
      writeEntries(subdir, zipFilePath, io)
    else
      io.get_output_stream(zipFilePath) { |f| f.puts(File.open(diskFilePath, "rb").read())}
    end
  } 
  end
end