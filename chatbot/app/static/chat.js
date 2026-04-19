function paddedHistoryId(value) {
  return String(value).padStart(3, "0");
}

async function loadHistory(limit = 50) {
  const response = await fetch(`/api/history?limit=${limit}`);
  if (!response.ok) {
    throw new Error(`History load failed (${response.status})`);
  }
  const data = await response.json();
  return data.items || [];
}

async function initChatPage() {
  const form = document.getElementById("chat-form");
  if (!form) {
    return;
  }

  const message = document.getElementById("message");
  const send = document.getElementById("send");
  const answer = document.getElementById("answer");
  const metadata = document.getElementById("metadata");
  const useRag = document.getElementById("use-rag");
  const useLocalFiles = document.getElementById("use-local-files");
  const useWeb = document.getElementById("use-web");
  const retrievalProfile = document.getElementById("retrieval-profile");
  const compareProfiles = document.getElementById("compare-profiles");
  const compareMode = document.getElementById("compare-mode");
  const compareSelectAll = document.getElementById("compare-select-all");
  const retrievalProfileBlock = document.getElementById("retrieval-profile-block");
  const compareProfilesBlock = document.getElementById("compare-profiles-block");
  const providerBlock = document.getElementById("provider-block");
  const modelBlock = document.getElementById("model-block");
  const historyList = document.getElementById("history-list");
  const historyRefresh = document.getElementById("history-refresh");
  const historyUse = document.getElementById("history-use");
  const historyClear = document.getElementById("history-clear");
  let historyItems = [];

  function setBlockState(element, {disabled = false, hidden = false} = {}) {
    if (!element) {
      return;
    }
    element.classList.toggle("is-disabled", disabled);
    element.classList.toggle("is-hidden", hidden);
  }

  function setDisabled(element, disabled) {
    if (element) {
      element.disabled = disabled;
    }
  }

  function syncChatUiState() {
    if (useLocalFiles.checked) {
      useRag.checked = false;
      compareMode.checked = false;
    }
    if (compareMode.checked) {
      useRag.checked = true;
      useLocalFiles.checked = false;
    }

    const ragActive = useRag.checked;
    const localFilesActive = useLocalFiles.checked;
    const compareActive = compareMode.checked;
    const showSingleProfile = ragActive && !compareActive;
    const showCompareProfiles = ragActive && compareActive;
    const allowWebSearch = !ragActive && !localFilesActive;

    setBlockState(retrievalProfileBlock, {hidden: !showSingleProfile});
    setBlockState(compareProfilesBlock, {hidden: !showCompareProfiles});
    setDisabled(retrievalProfile, !showSingleProfile);
    setDisabled(compareProfiles, !showCompareProfiles);
    setDisabled(compareSelectAll, !showCompareProfiles);
    setDisabled(useWeb, !allowWebSearch);

    if (!allowWebSearch) {
      useWeb.checked = false;
    }

    setBlockState(providerBlock, {disabled: false});
    setBlockState(modelBlock, {disabled: false});
  }

  async function refreshHistory() {
    if (!historyList) {
      return;
    }
    historyList.innerHTML = "";
    historyList.append(new Option("Loading history...", ""));
    historyItems = await loadHistory(50);
    historyList.innerHTML = "";
    if (historyItems.length === 0) {
      historyList.append(new Option("No history yet.", ""));
      return;
    }
    const sortedItems = [...historyItems].sort((left, right) => Number(left.id) - Number(right.id));
    for (const item of sortedItems) {
      historyList.append(new Option(`${paddedHistoryId(item.id)}: ${item.message}`, String(item.id)));
    }
  }

  function useSelectedHistoryQuestion() {
    const selected = historyItems.find((item) => String(item.id) === historyList.value);
    if (!selected) {
      return;
    }
    message.value = selected.message;
    message.focus();
  }

  try {
    const {data, profiles} = await loadRetrievalProfiles();
    retrievalProfile.innerHTML = "";
    compareProfiles.innerHTML = "";

    for (const profile of profiles) {
      const label = retrievalProfileLabel(profile);
      retrievalProfile.append(new Option(label, profile.name, false, profile.name === data.default_profile));
      compareProfiles.append(new Option(label, profile.name, false, true));
    }

    fitSelectToOptions(compareProfiles);
    updateSelectAllState(compareProfiles, compareSelectAll);
  } catch (error) {
    metadata.textContent = JSON.stringify({profile_load_error: String(error)}, null, 2);
  }

  compareSelectAll.addEventListener("change", () => setAllSelected(compareProfiles, compareSelectAll.checked));
  compareProfiles.addEventListener("change", () => updateSelectAllState(compareProfiles, compareSelectAll));
  useRag.addEventListener("change", syncChatUiState);
  useLocalFiles.addEventListener("change", syncChatUiState);
  compareMode.addEventListener("change", syncChatUiState);
  historyList.addEventListener("change", useSelectedHistoryQuestion);
  historyUse.addEventListener("click", useSelectedHistoryQuestion);

  message.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      form.requestSubmit();
    }
  });

  historyRefresh.addEventListener("click", async () => {
    try {
      await refreshHistory();
    } catch (error) {
      metadata.textContent = JSON.stringify({history_error: String(error)}, null, 2);
      historyList.innerHTML = "";
      historyList.append(new Option(`History unavailable: ${String(error)}`, ""));
    }
  });

  historyClear.addEventListener("click", async () => {
    if (!window.confirm("Clear chat history?")) {
      return;
    }
    try {
      await fetch("/api/history", {method: "DELETE"});
      await refreshHistory();
    } catch (error) {
      metadata.textContent = JSON.stringify({history_error: String(error)}, null, 2);
    }
  });

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    send.disabled = true;
    answer.textContent = "Running query...";
    metadata.textContent = "{}";

    const body = {
      message: message.value,
      provider: document.getElementById("provider").value || null,
      model: document.getElementById("model").value || null,
      retrieval_profile: retrievalProfile.value || null,
      use_rag: useRag.checked,
      use_local_files: useLocalFiles.checked,
      use_web_search: document.getElementById("use-web").checked
    };
    const commandToken = document.getElementById("command-token").value.trim();
    const headers = {"Content-Type": "application/json"};
    if (commandToken) {
      headers.Authorization = `Bearer ${commandToken}`;
    }

    try {
      const response = await fetch(compareMode.checked ? "/api/chat/compare" : "/api/chat", {
        method: "POST",
        headers,
        body: JSON.stringify(compareMode.checked ? {
          message: body.message,
          provider: body.provider,
          model: body.model,
          retrieval_profiles: selectedValues(compareProfiles).length > 0 ? selectedValues(compareProfiles) : [body.retrieval_profile]
        } : body)
      });
      const data = await response.json();
      answer.textContent = compareMode.checked
        ? (data.results || []).map((item) => `# ${retrievalProfileLabelByName(item.retrieval_profile)}\n${item.answer || ""}`).join("\n\n")
        : data.answer || "";
      metadata.textContent = JSON.stringify({
        source: data.source,
        provider: data.provider,
        model: data.model,
        tool: data.tool,
        metadata: data.metadata,
        compare: data.results
      }, null, 2);
    } catch (error) {
      answer.textContent = String(error);
    } finally {
      send.disabled = false;
      refreshHistory().catch(() => {});
    }
  });

  syncChatUiState();
  refreshHistory().catch((error) => {
    historyList.innerHTML = "";
    historyList.append(new Option(`History unavailable: ${String(error)}`, ""));
  });
}

initChatPage();
