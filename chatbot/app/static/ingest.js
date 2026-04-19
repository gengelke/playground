async function initIngestPage() {
  const ingestForm = document.getElementById("ingest-form");
  if (!ingestForm) {
    return;
  }

  const ingestProfiles = document.getElementById("ingest-profiles");
  const ingestSelectAll = document.getElementById("ingest-select-all");
  const ingestSend = document.getElementById("ingest-send");
  const ingestResult = document.getElementById("ingest-result");
  const ingestFiles = document.getElementById("ingest-files");

  try {
    const {profiles} = await loadRetrievalProfiles();
    ingestProfiles.innerHTML = "";

    for (const profile of profiles) {
      ingestProfiles.append(new Option(retrievalProfileLabel(profile), profile.name, false, true));
    }

    fitSelectToOptions(ingestProfiles);
    updateSelectAllState(ingestProfiles, ingestSelectAll);
  } catch (error) {
    ingestResult.textContent = JSON.stringify({profile_load_error: String(error)}, null, 2);
  }

  ingestSelectAll.addEventListener("change", () => setAllSelected(ingestProfiles, ingestSelectAll.checked));
  ingestProfiles.addEventListener("change", () => updateSelectAllState(ingestProfiles, ingestSelectAll));

  ingestForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    ingestSend.disabled = true;

    const paths = document.getElementById("ingest-paths").value
      .split(/\r?\n/)
      .map((path) => path.trim())
      .filter(Boolean);
    const reset = document.getElementById("ingest-reset").checked;
    const files = Array.from(ingestFiles.files || []);
    const profiles = selectedValues(ingestProfiles);
    const results = [];

    ingestResult.textContent = JSON.stringify({
      status: "starting",
      server_paths: paths,
      browser_files: files.map((file) => file.name),
      profiles,
      reset
    }, null, 2);

    try {
      if (paths.length > 0) {
        ingestResult.textContent = JSON.stringify({
          status: "ingesting server paths",
          server_paths: paths,
          browser_files: files.map((file) => file.name),
          profiles,
          reset,
          partial_results: results
        }, null, 2);

        const data = await fetchJsonWithTimeout("/api/ingest", {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: JSON.stringify({paths, reset, profiles})
        });
        results.push({server_paths: data});
        ingestResult.textContent = JSON.stringify({
          status: files.length > 0 ? "server paths finished" : "completed",
          partial_results: results
        }, null, 2);
      }

      if (files.length > 0) {
        ingestResult.textContent = JSON.stringify({
          status: "uploading browser files",
          server_paths: paths,
          browser_files: files.map((file) => file.name),
          profiles,
          reset,
          partial_results: results
        }, null, 2);

        const formData = new FormData();
        for (const file of files) {
          formData.append("files", file);
        }
        formData.append("reset", paths.length > 0 ? "false" : String(reset));
        if (profiles.length > 0) {
          formData.append("profiles", profiles.join(","));
        }
        const data = await fetchJsonWithTimeout("/api/ingest/files", {
          method: "POST",
          body: formData
        });
        results.push({browser_files: data});
      }

      if (results.length === 0) {
        results.push({error: "Enter at least one server path or choose at least one browser file."});
      }

      ingestResult.textContent = JSON.stringify(
        results.length === 1 ? results[0] : {status: "completed", results},
        null,
        2
      );
    } catch (error) {
      ingestResult.textContent = JSON.stringify({
        status: "failed",
        error: String(error),
        partial_results: results
      }, null, 2);
    } finally {
      ingestSend.disabled = false;
    }
  });
}

initIngestPage();
