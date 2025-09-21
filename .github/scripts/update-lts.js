// Node 18+/22, zero deps
import fs from 'node:fs'
import path from 'node:path'

const ROOT = process.cwd()
const VERSIONS = path.join(ROOT, 'versions.json')
const REPORT = path.join(ROOT, '.github', 'lts-report.md')

// --- Utility functions ---
function readJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8'))
}
function writeJson(p, obj) {
  fs.writeFileSync(p, JSON.stringify(obj, null, 2) + '\n')
}
function writeReport(lines) {
  fs.mkdirSync(path.dirname(REPORT), { recursive: true })
  fs.writeFileSync(REPORT, lines.join('\n') + '\n')
}

async function getJson(url) {
  const res = await fetch(url, {
    headers: { 'User-Agent': 'lts-updater', Accept: 'application/json' },
  })
  if (!res.ok) throw new Error(`GET ${url} -> ${res.status}`)
  const text = await res.text()
  try {
    return JSON.parse(text)
  } catch {
    throw new Error(`GET ${url} returned non-JSON (len=${text.length})`)
  }
}

// --- .NET: detect latest stable LTS major ---
async function getDotnetLtsMajor() {
  const idx = await getJson(
    'https://builds.dotnet.microsoft.com/dotnet/release-metadata/releases-index.json'
  )
  const list = Array.isArray(idx?.['releases-index']) ? idx['releases-index'] : []
  const lts = list
    .filter((x) => x?.['release-type'] === 'lts')
    .filter((x) => !String(x?.['latest-release'] || '').includes('-')) // exclude preview/rc
  if (!lts.length) throw new Error('No stable .NET LTS channels found')
  lts.sort((a, b) => parseInt(b['channel-version']) - parseInt(a['channel-version']))
  return parseInt(lts[0]['channel-version'], 10) // e.g. 8 → 10
}

// --- Python: detect latest active 3.x cycle ---
function cmpCyclesDesc(a, b) {
  const [amaj, amin] = String(a.cycle)
    .split('.')
    .map((n) => parseInt(n, 10))
  const [bmaj, bmin] = String(b.cycle)
    .split('.')
    .map((n) => parseInt(n, 10))
  if (bmaj !== amaj) return bmaj - amaj // higher major first
  return bmin - amin // higher minor first
}

async function getPythonLatestSupportedMinor() {
  const urls = [
    'https://endoflife.date/api/python.json',
    'https://endoflife.date/api/v1/python.json',
    'https://endoflife.date/api/v1/products/python',
  ]

  let data, lastErr
  for (const u of urls) {
    try {
      data = await getJson(u)
      break
    } catch (e) {
      lastErr = e
    }
  }
  if (!data) throw lastErr ?? new Error('Cannot fetch Python EOL data')

  // Normalize to an array of records
  let rows
  if (Array.isArray(data)) {
    rows = data
  } else if (Array.isArray(data?.cycles)) {
    rows = data.cycles
  } else if (Array.isArray(data?.releases)) {
    rows = data.releases
  } else {
    const maybeArrayKey = Object.keys(data).find((k) => Array.isArray(data[k]))
    if (maybeArrayKey) rows = data[maybeArrayKey]
  }
  if (!Array.isArray(rows)) {
    const keys = Object.keys(data || {})
    throw new Error(`Unexpected Python API shape. Keys: [${keys.join(', ')}]`)
  }

  const now = new Date()
  const active3x = rows
    .filter((x) => !!x?.cycle && String(x.cycle).startsWith('3.'))
    .filter((x) => !!x?.eol && new Date(x.eol) > now)

  if (!active3x.length) throw new Error('No supported Python 3.x cycles')

  active3x.sort(cmpCyclesDesc)
  return String(active3x[0].cycle) // e.g. "3.13"
}

// --- Main script ---
;(async () => {
  const current = readJson(VERSIONS)

  const nextDotnet = await getDotnetLtsMajor()
  const nextPy = await getPythonLatestSupportedMinor()

  const out = { ...current }
  const changes = []

  if (current.dotnetLtsMajor !== nextDotnet) {
    changes.push(`.NET LTS: ${current.dotnetLtsMajor} → ${nextDotnet}`)
    out.dotnetLtsMajor = nextDotnet
  }
  if (current.pythonSupportedMinor !== nextPy) {
    // Guard: do not downgrade if somehow API returns lower cycle
    const [curMaj, curMin] = String(current.pythonSupportedMinor).split('.').map(Number)
    const [newMaj, newMin] = String(nextPy).split('.').map(Number)
    const isUpgrade = newMaj > curMaj || (newMaj === curMaj && newMin > curMin)

    if (isUpgrade) {
      changes.push(`Python 3.x: ${current.pythonSupportedMinor} → ${nextPy}`)
      out.pythonSupportedMinor = nextPy
    }
  }

  const report = ['# LTS bump report', '']
  if (changes.length) {
    writeJson(VERSIONS, out)
    report.push(...changes.map((x) => `- ${x}`))
  } else {
    report.push('No changes (already latest LTS).')
  }
  writeReport(report)
})().catch((err) => {
  console.error(err)
  process.exit(1)
})
