const username = document.querySelector("#username"), password = document.querySelector("#password");
chrome.storage.local.get(["username", "password"], values => { username.value = values.username || ""; password.value = values.password || ""; });
document.querySelector("#save").onclick = () => chrome.storage.local.set({username: username.value.trim(), password: password.value}, () => window.close());
