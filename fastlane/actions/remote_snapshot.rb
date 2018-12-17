module Fastlane
  module Actions
    module SharedValues
      REMOTE_SCAN_CUSTOM_VALUE = :REMOTE_SCAN_CUSTOM_VALUE
    end

    class RemoteSnapshotAction < Action

      APP_PATH = 'iosapp_with_snapshot' # TODO extract from options[:project]   
      REPOSITORY = 'janpio/fastlane-runner'

      def self.run(params)

        # upload app
        upload_id = self.upload_app(APP_PATH)
        puts "app uploaded (upload_id = #{upload_id})"

        # trigger build for upload
        request_id = self.trigger_remote_action('snapshot', upload_id)
        puts "remote action triggered (request_id = #{request_id})"

        # poll request/build status
        spinner = TTY::Spinner.new("[:spinner] Waiting for remote action to finish...", format: :dots)
        spinner.auto_spin
        build = self.retrieve_build(REPOSITORY, request_id)
        log = self.wait_and_retrieve_log(build)
        spinner.success("Done")

        # output log
        self.output_log(log)

        # Actions.lane_context[SharedValues::REMOTE_SCAN_CUSTOM_VALUE] = "my_val"
      end

      def self.upload_app(app_path)
        zip_content_path = "#{app_path}/.."
        
        # calculate checksum of app
        checksum = Zlib::crc32(Dir.glob("#{zip_content_path}/**/*").map { |name| [name, File.mtime(name)] }.to_s)
    
        # archive app
        archive = "#{checksum}.zip"
        if(!File.exist?(archive))
          zf = ZipFileGenerator.new(zip_content_path, archive)
          zf.write()
        end
    
        # upload archive
        upload_id = upload_file(archive)
        # TODO skip additional upload if file was uploaded before 
        # (assumption: if archive already existed, it was also uploaded: check via new API if true)  end

        # TODO handle eventual upload errors
      end
    
      def self.upload_file(filename)
        require 'net/http/post/multipart'
    
        url = URI.parse('http://remote-fastlane.betamo.de/upload.php')
        File.open(filename) do |file|
          req = Net::HTTP::Post::Multipart.new url.path,
            "datei" => UploadIO.new(file, "application/zip", filename)
          res = Net::HTTP.start(url.host, url.port) do |http|
            return http.request(req).body
          end
        end
      end
    
      def self.trigger_remote_action(action, upload_id)
        url = "http://remote-fastlane.betamo.de/trigger_build.php?upload_id=#{upload_id}&action=#{action}"
        # TODO use action to define different actions to trigger
        puts url;
        created_request = other_action.download(url: url)
        # TODO handle eventual errors
        created_request['request']['id']
      end
    
      def self.retrieve_build(repository, request_id)
        require 'travis/client'
        Travis.connect
        repo = Travis::Repository.find(slug: repository)
        requests = repo.requests
        request = self.extract_request(requests, request_id);
        builds = request.builds
        build = builds.first
      end
    
      def self.extract_request(requests, request_id)
        requests.each do |request|
          return request if request.id == request_id
        end
        return nil
      end
    
      def self.wait_and_retrieve_log(build)
        loop do
          build2 = Travis::Build.find(id: build.id)
    
          # TODO start outputting log as soon as build is started
    
          # wait: :created, :received, :started, 
          # break: :passed, :failed, :errored, :canceled
          processing = (build2.state == 'created' || build2.state == 'received'  || build2.state == 'started')
          return build2 if !processing
    
          sleep(3)
        end
      end
    
      def self.output_log(build2)
        log = build2.jobs.first.log
    
        full_log = log.content
    
        # extract relevant log
        relevant_log = ''
        keep = false
        start_line = /Cruising over to lane 'test'/
        end_line = /Cruising back to lane 'remote_scan'/
        full_log.each_line do |line|
          keep = false if line =~ end_line
          relevant_log = relevant_log + line if keep == true
          keep = true if line =~ start_line
          # TODO remove travis stuff
        end
        puts relevant_log
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
  entries = Dir.entries(@inputDir); entries.delete("."); entries.delete("..")
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