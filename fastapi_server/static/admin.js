let savedToken = ''

function saveToken(){
  savedToken = document.getElementById('token').value.trim()
  alert('token saved (in page)')
}

async function updateParam(btn){
  const input = btn.parentElement.querySelector('.pvalue')
  const name = input.dataset.name
  const value = input.value
  if(!savedToken){ alert('لطفا توکن را وارد کنید'); return }
  const res = await fetch('/params/' + encodeURIComponent(name), {
    method: 'PUT',
    headers: { 'Content-Type':'application/json', 'Authorization': 'Bearer ' + savedToken },
    body: JSON.stringify({ name, value })
  })
  if(res.ok){ alert('OK') } else { alert('Error') }
}

async function refreshLogs(){
  if(!savedToken){ alert('لطفا توکن را وارد کنید'); return }
  const res = await fetch('/logs?limit=200', { headers: { 'Authorization': 'Bearer ' + savedToken } })
  if(!res.ok){ alert('Error fetching logs'); return }
  const logs = await res.json()
  const container = document.getElementById('logs')
  container.innerHTML = ''
  for(const l of logs){
    const d = document.createElement('div')
    d.className = 'log-item'
    d.textContent = `[${l.timestamp}] ${l.level} - ${l.message}`
    container.appendChild(d)
  }
}
