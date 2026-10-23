// Puente mínimo entre la pantalla Cultura y la extensión local de Chrome.
window.addEventListener("message", event => {
  if (event.source !== window || event.data?.type !== "CULTURA_PPL_SEARCH") return;
  chrome.runtime.sendMessage({type: "SEARCH", requestId: event.data.requestId, payload: event.data.payload}, response => {
    const error = chrome.runtime.lastError?.message || response?.error;
    window.postMessage({type: "CULTURA_PPL_RESULT", requestId: event.data.requestId, rows: response?.rows || [], error}, window.location.origin);
  });
});
