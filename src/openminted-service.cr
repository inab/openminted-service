require "./openminted-service/*"
require "file_utils"
require "json"
require "kemal"

# TODO
# Use document system
# Multiple readers, single writter
# Check uuid using a block decorator
# Customize 404 error
# Send error codes

module Openminted::Service
  extend self

  enum Status
    Accepted
    Running
    Finished
  end

  # cas_has use uuid as key and a hash as value with the file uploaded (written as filename + _UUID) and its status
  cas_hash = Hash(String, Hash(Symbol, String | Status)).new
  cas_mutex = Channel(Nil).new(1)
  cas_mutex.send(nil)

  URL_PATHS = {"url"           => "process",
               "casUrl"        => "cas",
               "typeSystemUrl" => "typeSystem",
               "deletionUrl"   => "process"}

  CAS_FOLDER = File.join Kemal.config.public_folder, "cas"

  # get "/" do
  # uuid = SecureRandom.uuid
  # cas_mutex.receive
  # uuids[uuid] = Status::Accepted
  # cas_mutex.send(nil)
  # uuid
  # end
  def resolve_cas_path(cas_hash, cas_id)
    File.join CAS_FOLDER, "#{cas_hash[cas_id][:filename].as(String)}_#{cas_id}"
  end

  get "/cas_hash" do |env|
    env.response.content_type = "application/json"

    cas_hash_tmp = cas_hash.dup
    cas_hash_tmp.each do |k, v|
      v[:status] = v[:status].to_s
    end
    cas_hash_tmp.to_json
  end
  get "/cas_folder" do |env|
    env.response.content_type = "application/json"
    Dir.entries(CAS_FOLDER).select { |entrie| entrie != "." && entrie != ".." }.to_json
  end

  # Have to be POST and accept a VALID XMI file
  # Process CAS
  # curl -F cas=@/some/file/on/your/local/disk http://localhost:3000/process
  post "/process" do |env|
    # https://openminted.github.io/releases/processing-web-services/1.0.0/specification#_process_cas
    cas_file = env.params.files["cas"]
    cas_filename = cas_file.filename
    uuid = SecureRandom.uuid

    if cas_filename.is_a?(String)
      cas_mutex.receive
      real_cas_path = ::File.join [CAS_FOLDER, cas_filename + "_#{uuid}"]

      File.open(real_cas_path, "w") do |f|
        IO.copy(cas_file.tmpfile, f)
      end

      host = env.request.headers["Host"]
      uri = env.request.path
      # status = Status::Accepted
      status = Status::Finished
      cas_hash[uuid] = {:filename => cas_filename, :status => status}
      cas_mutex.send(nil)

      env.response.content_type = "application/json"
      {:url => "#{host}#{uri}/#{uuid}", :status => status.to_s}.to_json
    end
  end

  # Get process status
  get "/process/:process_id" do |env|
    process_id = env.params.url["process_id"]
    host = env.request.headers["Host"]

    env.response.content_type = "application/json"

    response = ""

    if cas_hash[process_id]?
      response = Hash(String, String).new
      URL_PATHS.each do |k, v|
        response[k] = "#{host}/#{v}/#{process_id}"
      end
      response["status"] = cas_hash[process_id][:status].to_s
    end
    response.to_json
  end

  # curl -X 'DELETE' 'http://localhost:3000/process/process_id'
  delete "/process/:process_id" do |env|
    process_id = env.params.url["process_id"]

    if cas_hash[process_id]?
      cas_mutex.receive
      real_cas_path = resolve_cas_path(cas_hash, process_id)
      FileUtils.rm(real_cas_path)
      cas_hash.delete process_id
      cas_mutex.send(nil)
    end

    nil
  end

  get "/cas/:process_id" do |env|
    process_id = env.params.url["process_id"]
    host = env.request.headers["Host"]

    real_cas_path = ""
    if cas_hash[process_id]? && (cas_hash[process_id][:status] == Status::Finished)
      puts "Sending XML..."
      real_cas_path = resolve_cas_path(cas_hash, process_id)
      # send_file env, real_file_path
    end
    # File.read(real_cas_path) if File.file? real_cas_path

    env.response.content_type = "application/vnd.xmi+xml"
    send_file env, real_cas_path if File.file? real_cas_path
  end

  Kemal.config.host_binding = "0.0.0.0"
  # Kemal.config.env = "production"
  Kemal.run
end
