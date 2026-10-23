// La consulta se ejecuta en un documento offscreen: no abre pestañas ni ventanas.
async function ensureOffscreen() {
  const contexts = await chrome.runtime.getContexts({contextTypes: ["OFFSCREEN_DOCUMENT"]});
  if (!contexts.length) await chrome.offscreen.createDocument({url:"offscreen.html",reasons:["DOM_PARSER"],justification:"Consultar y leer la tabla institucional de PPLs sin mostrar una pestaña."});
}
chrome.runtime.onMessage.addListener((message,sender,sendResponse)=>{
  if(message.type!=="SEARCH")return;
  (async()=>{try{await ensureOffscreen();const credentials=await chrome.storage.local.get(["username","password"]);sendResponse(await chrome.runtime.sendMessage({type:"OFFSCREEN_SEARCH",payload:message.payload,credentials}));}catch(error){sendResponse({error:error.message||"ERROR INESPERADO EN LA BÚSQUEDA."});}})();
  return true;
});
