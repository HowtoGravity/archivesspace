# runs the bulk_importer

require_relative "../streaming_import"
require_relative "../bulk_import/import_archival_objects"
require_relative "../bulk_import/import_digital_objects"
require "csv"

class Ticker
  def initialize(job)
    @job = job
  end

  def tick
  end

  def status_update(status_code, status)
    @job.write_output("#{status[:id]}. #{status_code.upcase}: #{status[:label]}")
  end

  def log(s)
    @job.write_output(s)
  end

  def tick_estimate=(n)
  end
end

class BulkImportRunner < JobRunner
  register_for_job_type("bulk_import_job", :create_permissions => :import_records,
                                           :cancel_permissions => :cancel_importer_job, :hidden => true)

  def run
    ticker = Ticker.new(@job)
    ticker.log("Start new bulk_import ")
    last_error = nil
    batch = nil
    success = false
    jobfiles = @job.job_files || []
    filenames = [@json.job["file_name"]]
    # Wrap the import in a transaction if the DB supports MVCC
    begin
      DB.open(DB.supports_mvcc?,
              :retry_on_optimistic_locking_fail => true) do
        begin
          @input_file = @job.job_files[0].full_file_path
          @current_user = User.find(:username => @job.owner.username)
          @load_type = @json.job["load_type"]
          # I don't know whay this parsing is so hard!!
          param_string = @json.job_params[1..-2].delete('\\\\')
          params = ASUtils.json_parse(param_string)
          params = symbol_keys(params)
          ticker.log(("=" * 50) + "\n#{@json.job["filename"]}\n" + ("=" * 50))
          begin
            RequestContext.open(:create_enums => true,
                                :current_username => @job.owner.username,
                                :repo_id => @job.repo_id) do
              #               converter.run(@job[:job_blob])
              success = true
              importer = get_importer(@json.job["content_type"], params, ticker.method(:log))

              report = importer.run
              if !report.terminal_error.nil?
                msg = I18n.t("bulk_import.error.error", :term => report.terminal_error)
              else
                msg = I18n.t("bulk_import.processed")
              end
              ticker.log(msg)
              ticker.log(("=" * 50) + "\n")
              ticker.log(I18n.t("bulk_import.log_complete", :file => @json.job["filename"]))
              ticker.log("\n" + ("=" * 50) + "\n")
              file = ASUtils.tempfile("load_spreadsheet_job_")
              generate_csv(file, report)
              file.rewind
              @job.write_output(I18n.t("bulk_import.log_results"))
              Log.error(@job.inspect)
              @job.add_file(file)
            end
          end
        rescue JSONModel::ValidationException, BulkImportException => e
          last_error = e
        end
      end
    rescue
      last_error = $!
    end
    self.success!
    if last_error
      ticker.log("\n\n")
      ticker.log("!" * 50)
      ticker.log("IMPORT ERROR")
      ticker.log("!" * 50)
      ticker.log("\n\n")

      if last_error.respond_to?(:errors)
        ticker.log("#{last_error}") if last_error.errors.empty? # just spit it out if there's not explicit errors

        ticker.log("The following errors were found:\n")

        last_error.errors.each_pair { |k, v| ticker.log("\t#{k.to_s} : #{v.join(" -- ")}") }
      else
        ticker.log("Error: #{CGI.escapeHTML(last_error.inspect)}")
      end
      ticker.log("!" * 50)
      raise last_error
    end
  end

  private

  def generate_csv(file, report)
    headrow = I18n.t("bulk_import.clip_header").split('\t')
    CSV.open(file.path, "wb") do |csv|
      csv << headrow
      csv << []
      report.rows.each do |row|
        csvrow = [row.row]
        if row.archival_object_id.nil?
          if @load_type == "digital"
            csvrow = []
          else
            csvrow << I18n.t("bulk_import.no_ao")
          end
        else
          if @load_type == "digital"
            csvrow << I18n.t("bulk_import.ao")
            csvrow << "#{row.archival_object_display}"
            csvrow << row.archival_object_id
            csvrow << "#{row.ref_id}"
          elsif @load_type == "ao"
            csvrow << I18n.t("bulk_import.object_created", :what => I18n.t("bulk_import.ao"))
            csvrow << "#{row.archival_object_display}"
            csvrow << row.archival_object_id
            csvrow << "#{row.ref_id}"
          end
        end
        csv << csvrow if !csvrow.empty?
        unless row.info.empty?
          row.info.each do |info|
            csvrow = Array.new(5, "")
            csvrow[0] = row.row
            csvrow << info
            csv << csvrow
          end
        end
        unless row.errors.empty?
          row.errors.each do |err|
            csvrow = Array.new(5, "")
            csvrow[0] = row.row
            csvrow << err
            csv << csvrow
          end
        end
      end
    end
  end

  def get_importer(content_type, params, log_method)
    importer = nil
    if @load_type == "digital"
      importer = ImportDigitalObjects.new(@input_file, content_type, @current_user, params, log_method)
    elsif @load_type == "ao"
      importer = ImportArchivalObjects.new(@input_file, content_type, @current_user, params, log_method)
    end
    importer
  end

  def process_report(report)
    output = ""
    report.rows.each do |row|
      output += row.row
      if row.archival_object_id.nil?
        output += " " + I18n.t("bulk_import.no_ao") if !@dig_o
      else
        if @dig_o
          output += I18n.t("bulk_import.clip_what", :what => I18n.t("bulk_import.ao"), :id => row.archival_object_id,
                                                    :nm => "'#{row.archival_object_display}'",
                                                    :ref_id => "#{row.ref_id}")
        else
          output += I18n.t("bulk_import.clip_created", :what => I18n.t("bulk_import.ao"), :id => row.archival_object_id,
                                                       :nm => "'#{row.archival_object_display}'",
                                                       :ref_id => "#{row.ref_id}")
        end
      end
      output += "\n"
      unless row.info.empty?
        row.info.each do |info|
          output += I18n.t("bulk_import.clip_info", :what => info) + "\n"
        end
      end
      unless row.errors.empty?
        row.errors.each do |err|
          output += I18n.t("bulk_import.clip_err", :err => err) + "\n"
        end
      end
    end
    output
  end

  def symbol_keys(hash)
    h = hash.map do |k, v|
      v_sym = if v.instance_of? Hash
          v = symbol_keys(v)
        else
          v
        end

      [k.to_sym, v_sym]
    end
    Hash[h]
  end
end
