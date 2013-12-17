class ArchivesSpaceService < Sinatra::Base

  Endpoint.post('/repositories/:repo_id/jobs')
    .description("Create a new import job")
    .params(["job", JSONModel(:job)],
            ["files", [UploadFile]],
            ["repo_id", :repo_id])
    .permissions([:update_archival_record])
    .returns([200, :updated]) \
  do
    job = ImportJob.create_from_json(params[:job], :user => current_user)

    params[:files].each do |file|
      job.add_file(file.tempfile)
    end

    created_response(job, params[:job])
  end

  Endpoint.post('/repositories/:repo_id/jobs/:id/cancel')
    .description("Create a new import job")
    .params(["id", :id],
            ["repo_id", :repo_id])
    .permissions([:cancel_importer_job])
    .returns([200, :updated]) \
  do
    # cancel the job!
  end

  Endpoint.get('/repositories/:repo_id/jobs')
    .description("Get a list of Jobs for a Repository")
    .params(["mtime", DateTime, "Only return jobs that have changed after a given timestamp", :optional => true],
            ["repo_id", :repo_id])
    .paginated(true)
    .permissions([:view_repository])
    .returns([200, "[(:job)]"]) \
  do
    if params[:mtime]
      # return only the jobs that have changed
    else
      handle_listing(ImportJob, params, {}, [:status, :id])
    end
  end


  Endpoint.get('/repositories/:repo_id/jobs/active')
    .description("Get a list of all active Jobs for a Repository")
    .params(["resolve", :resolve],
            ["repo_id", :repo_id])
    .permissions([:view_repository])
    .returns([200, "[(:job)]"]) \
  do
    running = CrudHelpers.scoped_dataset(ImportJob, :status => "running")
    queued = CrudHelpers.scoped_dataset(ImportJob, :status => "queued")

    active = (running.all + queued.all).sort{|a,b| b.system_mtime <=> a.system_mtime}

    listing_response(active, ImportJob)
  end


  Endpoint.get('/repositories/:repo_id/jobs/archived')
    .description("Get a list of all archived Jobs for a Repository")
    .params(["resolve", :resolve],
            ["repo_id", :repo_id])
    .permissions([:view_repository])
    .paginated(true)
    .returns([200, "[(:job)]"]) \
  do
    handle_listing(ImportJob, params, Sequel.~(:status => ["running", "queued"]), Sequel.desc(:time_finished))
  end


  Endpoint.get('/repositories/:repo_id/jobs/:id')
    .description("Get a Job by ID")
    .params(["id", :id],
            ["resolve", :resolve],
            ["repo_id", :repo_id])
    .permissions([:view_repository])
    .returns([200, "(:job)"]) \
  do
    json_response(resolve_references(ImportJob.to_jsonmodel(params[:id]), params[:resolve]))
  end


  Endpoint.get('/repositories/:repo_id/jobs/:id/log')
    .description("Get a Job's log by ID")
    .params(["id", :id],
            ["repo_id", :repo_id])
    .permissions([:view_repository])
    .returns([200, "Stream"]) \
  do
    # return job's log as a stream
  end


  Endpoint.get('/repositories/:repo_id/jobs/:id/uris')
    .description("Get the URI's created by a Job")
    .params(["id", :id],
            ["repo_id", :repo_id])
    .permissions([:view_repository])
    .returns([200, "Stream"]) \
  do
    # return uri's as a stream
  end
end
