function selectedValues(select) {
  return Array.from(select.selectedOptions).map((option) => option.value).filter(Boolean);
}

function setAllSelected(select, selected) {
  for (const option of select.options) {
    option.selected = selected;
  }
}

function updateSelectAllState(select, checkbox) {
  if (!select || !checkbox) {
    return;
  }
  const options = Array.from(select.options);
  checkbox.checked = options.length > 0 && options.every((option) => option.selected);
}

function fitSelectToOptions(select) {
  if (!select) {
    return;
  }
  select.size = Math.max(1, select.options.length);
}

function retrievalProfileLabel(profile) {
  const labels = {
    sqlite: "SQLite keyword search",
    qdrant_openai: "Qdrant semantic search - OpenAI embeddings",
    qdrant_ollama: "Qdrant semantic search - Ollama embeddings"
  };
  return labels[profile.name] || profile.name;
}

function retrievalProfileLabelByName(name) {
  return retrievalProfileLabel({name});
}

function textForCopy(element) {
  if (!element) {
    return "";
  }
  if ("value" in element) {
    return element.value;
  }
  return element.textContent || "";
}

async function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    await navigator.clipboard.writeText(text);
    return;
  }

  const fallback = document.createElement("textarea");
  fallback.value = text;
  fallback.setAttribute("readonly", "");
  fallback.style.position = "fixed";
  fallback.style.left = "-9999px";
  document.body.appendChild(fallback);
  fallback.select();
  document.execCommand("copy");
  fallback.remove();
}

function initCopyButtons() {
  for (const button of document.querySelectorAll("[data-copy-target]")) {
    button.addEventListener("click", async () => {
      const target = document.getElementById(button.dataset.copyTarget);
      const originalText = button.textContent;
      try {
        await copyText(textForCopy(target));
        button.textContent = "Copied";
      } catch (error) {
        button.textContent = "Failed";
      } finally {
        window.setTimeout(() => {
          button.textContent = originalText;
        }, 1200);
      }
    });
  }
}

async function loadRetrievalProfiles() {
  const response = await fetch("/api/retrieval-profiles");
  const data = await response.json();
  const profiles = data.profiles || [];
  return {data, profiles};
}

async function fetchJsonWithTimeout(url, options = {}, timeoutMs = 180000) {
  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {...options, signal: controller.signal});
    const text = await response.text();
    let data;
    try {
      data = text ? JSON.parse(text) : {};
    } catch (_error) {
      data = {raw: text};
    }
    if (!response.ok) {
      throw new Error(`Request failed (${response.status}): ${JSON.stringify(data)}`);
    }
    return data;
  } catch (error) {
    if (error.name === "AbortError") {
      throw new Error(`Request timed out after ${Math.round(timeoutMs / 1000)} seconds.`);
    }
    throw error;
  } finally {
    window.clearTimeout(timer);
  }
}

initCopyButtons();
