import fs from 'node:fs'
import path from 'node:path'

const ROOT = process.cwd()
const VERSIONS = path.join(ROOT, 'versions.json')
const REPORT = path.join(ROOT, '.github', 'lts-report.md')

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf-8'))
}

function writeJson(p, obj) {
  fs.writeFileSync(p, JSON.stringify(obj, null, 2) + '\n')
}

function writeReport(lines) {
  fs.mkdirSync(path.dirname(REPORT), { recursive: true })
  fs.writeFileSync(REPORT, lines.join('\n') + '\n')
}

async function getJson(url) {
  const response = await fetch(url, {
    headers: {
      'User-Agent': 'lts-updater',
    },
  })

  if (!response.ok) throw new Error(`GET ${url} -> ${response.status}`)

  return response.json()
}

async function getDotnetLtsMajor() {
  const idx = await getJson(
    'https://builds.dotnet.microsoft.com/dotnet/release-metadata/releases-index.json'
  )

  const lts = idx['releases-index']
    .filter((x) => x['release-type'] === 'lts')
    .filter((x) => !String(x['latest-release'] || '').includes('-')) // without preview/rc

  if (!lts.length) throw new Error('No stable .NET LTS channels found')

  lts.sort((a, b) => parseInt(b['channel-version']) - parseInt(a['channel-version']))

  return parseInt(lts[0]['channel-version'], 10) // np. 8 → 10
}

async function getPythonLatestSupportedMinor() {
  const list = await getJson('https://endoflife.date/api/v1/products/python')

  const now = new Date()
  const active3x = list
    .filter((x) => x.cycle && x.cycle.startsWith('3.'))
    .filter((x) => x.eol && new Date(x.eol) > now)

  if (!active3x.length) throw new Error('No supported Python 3.x cycles')

  active3x.sort((a, b) => parseFloat(b.cycle) - parseFloat(a.cycle))
  return active3x[0].cycle // np. "3.13"
}

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
    changes.push(`Python 3.x: ${current.pythonSupportedMinor} → ${nextPy}`)
    out.pythonSupportedMinor = nextPy
  }

  const report = ['# LTS bump report', '']
  if (changes.length) {
    writeJson(VERSIONS, out)
    report.push(...changes.map((x) => `- ${x}`))
  } else {
    report.push('No changes detected (already have the LTS).')
  }
  writeReport(report)
})().catch((err) => {
  console.error(err)
  process.exit(1)
})
