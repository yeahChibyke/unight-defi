import { StrictMode, useMemo, useState } from 'react'
import { createRoot } from 'react-dom/client'
import './styles.css'

const BRAND_IMAGE = '/assets/unight.png'

const params = {
  tick: -64451, lower: -70790, upper: -56920,
  terminal: 124850, globalCap: 1000000,
  autoCap: 600000, bidCap: 400000, reserve: 100000,
  maturity: '25 Sep 2026', market: 'USDC / cbBTC',
  marketId: '0x549c…f221', account: '0xFEE7…5F24',
  forkBlock: '50,000,000'
}
type Mode = 'auto' | 'bid'

function money(n: number) { return '$' + n.toLocaleString('en-US', { maximumFractionDigits: 0 }) }

function Logo({ size = 28 }: { size?: number }) {
  return (
    <img src={BRAND_IMAGE} width={size} height={size} className="logo" alt="Unight mark" />
  )
}

const modeMeta: Record<Mode, { eyebrow: string; title: string; lede: string; icon: string; steps: string[] }> = {
  auto: {
    eyebrow: 'OFFER 01 · BORROWER SPEAKS FIRST',
    title: 'Auto-Lend',
    lede: 'Unight watches the Morpho-hosted ask books and takes a qualifying borrower ask the moment it clears your policy — no action required.',
    icon: '↗',
    steps: [
      'Borrower ask discovered',
      'Offer ratified by Midnight',
      'Unight removes exact terminal principal',
      'LP receives Midnight credit'
    ]
  },
  bid: {
    eyebrow: 'OFFER 02 · LP SPEAKS FIRST',
    title: 'LP Bid Board',
    lede: 'You sign a callback-backed Midnight buy offer and publish your own price and visible lending capacity for borrowers to fill.',
    icon: '⌁',
    steps: [
      'LP publishes signed bid',
      'Borrower accepts the offer',
      'Unight validates callback context',
      'LP receives Midnight credit'
    ]
  }
}

function App() {
  const [mode, setMode] = useState<Mode>('auto')
  const [amount, setAmount] = useState(20000)
  const [rate, setRate] = useState(8.5)
  const [settled, setSettled] = useState(false)
  const [open, setOpen] = useState<number | null>(0)

  const cap = mode === 'auto' ? params.autoCap : params.bidCap
  const available = Math.min(cap, params.terminal - params.reserve)
  const valid = amount > 0 && amount <= available
  const progress = Math.min(100, (amount / available) * 100)
  const meta = modeMeta[mode]

  const faq = [
    ['What is Unight?', 'Unight turns safely dormant Uniswap v4 liquidity — a single out-of-range position whose principal is entirely the loan token — into bounded, fixed-maturity credit exposure on Morpho Midnight, without moving the LP position.'],
    ['How does the LP keep their position?', 'The capital source is untouched until a Midnight settlement actually consumes it. A policy-controlled Unight Account custodies the position NFT and only decreases liquidity just in time through a Midnight buy callback.'],
    ['How are Auto-Lend and the Bid Board different?', 'In Auto-Lend the borrower speaks first: Unight takes an eligible ask for you. In the LP Bid Board you speak first: you sign a callback-backed bid and publish your own price and visible capacity. Both settle atomically through Midnight.'],
    ['Is this double yield on the same capital?', 'No. A successful fill converts part of your immediately available AMM inventory into fixed-maturity credit that remains exposed until it is sold, repaid, or withdrawn. Reaching maturity does not guarantee immediate cash.'],
    ['Which token and market initially?', 'Unight v1 lends USDC from fully out-of-range positions into approved Morpho Midnight fixed-maturity markets on Base mainnet (chain 8453).'],
    ['Is Unight live today?', 'Unight is a development prototype. The contracts are not audited. This simulator runs a deterministic demo on pinned Base fork block 50,000,000 — please do not deposit real funds.']
  ]

  return (
    <div className="site">
      <header className="mast">
        <div className="mast-inner">
          <a className="brand" href="#top"><Logo size={30} /><span>unight<span className="brand-dot">.</span>finance</span></a>
          <nav className="nav">
            <a href="#offers">Offers</a>
            <a href="#how">How it works</a>
            <a href="#simulator">Simulator</a>
            <a href="#faq">FAQ</a>
          </nav>
          <div className="mast-cta"><a className="btn ghost" href="#simulator">Open simulator <span>→</span></a></div>
        </div>
      </header>

      <main id="top">
        <section className="hero">
          <div className="hero-glow" aria-hidden="true"/>
          <div className="hero-inner">
            <h1>Conditional fixed-rate lending for out-of-range Uniswap v4 liquidity.</h1>
            <p className="lede">Unight lets Uniswap v4 LPs lend a controlled portion of their idle, out-of-range liquidity on Morpho Midnight — without withdrawing the position.</p>
          </div>
        </section>

        <section className="offers" id="offers">
          <div className="sec-head">
            <span className="eyebrow">01 — The two lending offers</span>
            <h2>Two ways to lend from one position.</h2>
            <p className="sec-sub">Choose whether the borrower finds you or you set the offer. Both options lend only within your limits, use the same idle inventory, and settle atomically through Morpho Midnight.</p>
          </div>
          <div className="offer-grid">
            <article className={mode === 'auto' ? 'offer-card selected' : 'offer-card'} onClick={() => { setMode('auto'); setSettled(false) }}>
              <div className="offer-top"><span className="offer-icon">↗</span><span className="chip">Borrower speaks first</span></div>
              <h3>Auto-Lend</h3>
              <p>Set your limits once. Unight monitors eligible Morpho Midnight borrower asks and takes qualifying offers for you.</p>
              <ul className="offer-points">
                <li>Watches Morpho-hosted ask books</li>
                <li>Offer ratified by Midnight</li>
                <li>No action after policy is set</li>
              </ul>
              <div className="offer-foot"><span>Cap <b>{money(params.autoCap)}</b></span><span className="more">Configure <span>→</span></span></div>
            </article>
            <article className={mode === 'bid' ? 'offer-card selected' : 'offer-card'} onClick={() => { setMode('bid'); setSettled(false) }}>
              <div className="offer-top"><span className="offer-icon gold">⌁</span><span className="chip">LP speaks first</span></div>
              <h3>LP Bid Board</h3>
              <p>Set your rate and capacity. Publish a signed lending offer for borrowers to discover and fill.</p>
              <ul className="offer-points">
                <li>Publish your own rate &amp; depth</li>
                <li>Borrower submits the signed offer</li>
                <li>Distributed via Unight Bid Board</li>
              </ul>
              <div className="offer-foot"><span>Cap <b>{money(params.bidCap)}</b></span><span className="more">Configure <span>→</span></span></div>
            </article>
          </div>
        </section>

        <section className="how" id="how">
          <div className="how-inner">
            <span className="eyebrow ondark">02 — How a settlement happens</span>
            <h2>Keep the position. Lend what is idle.</h2>
            <p className="sec-sub ondark">When a borrower fills an eligible offer, Unight removes only the required token amount and funds the Midnight loan in the same transaction. If any policy check fails, everything reverts.</p>
            <ol className="step-grid">
              {meta.steps.map((s, i) => (
                <li key={s}>
                  <span className="step-num">{String(i + 1).padStart(2, '0')}</span>
                  <span className="step-line" aria-hidden="true"/>
                  <h3>{s}</h3>
                </li>
              ))}
            </ol>
          </div>
        </section>

        <section className="sim" id="simulator">
          <div className="sim-shell">
            <div className="sim-flow">
              <div className="sec-head slim">
                <span className="eyebrow">03 — Live protocol flow</span>
                <h2>Watch a settlement happen.</h2>
              </div>
              <div className="position-card">
                <div className="range-head"><span>cbBTC price range</span><b>{params.lower.toLocaleString()} — {params.upper.toLocaleString()}</b></div>
                <div className="range"><i className="tick-marker" style={{ left: '45%' }} /></div>
                <div className="range-foot"><span className="chip">Position #2,742,919</span><span className="ok">● Dormant &amp; eligible</span><b className="tick">current tick {params.tick.toLocaleString()}</b></div>
              </div>
              <div className="flow-steps">
                {meta.steps.map((s, i) => (
                  <div className={settled || i === 0 ? 'fstep active' : 'fstep'} key={s}>
                    <span className="fstep-num">{settled || i === 0 ? '✓' : `0${i + 1}`}</span>
                    <span>{s}</span>
                  </div>
                ))}
              </div>
              <div className={settled ? 'result success' : 'result'}>
                <span className="result-icon">{settled ? '✓' : '↯'}</span>
                <div>
                  <strong>{settled ? 'Settlement simulated successfully' : 'Ready for a safe settlement'}</strong>
                  <small>{settled ? `${money(amount)} USDC funded at ${rate.toFixed(1)}% fixed rate` : 'Adjust the parameters, then run the flow on the right.'}</small>
                </div>
              </div>
            </div>

            <div className="sim-panel glass">
              <div className="sim-head">
                <div><span className="eyebrow">Interactive simulator</span><h2>Choose a lending mode</h2></div>
                <span className="chip gold">Pinned fork</span>
              </div>
              <div className="tabs">
                <button className={mode === 'auto' ? 'selected' : ''} onClick={() => { setMode('auto'); setSettled(false) }}><span>↗</span><strong>Auto-Lend</strong><small>Unight finds the borrower</small></button>
                <button className={mode === 'bid' ? 'selected' : ''} onClick={() => { setMode('bid'); setSettled(false) }}><span>⌁</span><strong>LP Bid Board</strong><small>You set the price</small></button>
              </div>
              <label className="field">Funding amount <output>{money(amount)} USDC</output></label>
              <div className="range-wrap">
                <input type="range" min="5000" max={available} step="5000" value={amount} onChange={e => { setAmount(+e.target.value); setSettled(false) }} />
                <div className="range-lims"><span>$5k</span><span>{money(available)} available</span></div>
              </div>
              <div className="capacity">
                <span>Mode capacity</span><span>{money(cap)} <b>{Math.round(progress)}%</b></span>
                <div className="cap-track"><i style={{ width: `${progress}%` }} /></div>
              </div>
              <label className="field">Minimum net rate <output>{rate.toFixed(1)}%</output></label>
              <div className="range-wrap">
                <input type="range" min="0" max="20" step="0.5" value={rate} onChange={e => setRate(+e.target.value)} />
              </div>
              <button className="btn primary run" disabled={!valid} onClick={() => setSettled(true)}>{mode === 'auto' ? 'Simulate Auto-Lend' : 'Simulate Bid Fill'} <span>→</span></button>
              <p className="fine">No wallet required · deterministic demo using the pinned Base block {params.forkBlock}</p>
            </div>
          </div>
        </section>

        <section className="owners" id="owners">
          <span className="eyebrow">04 — For liquidity providers</span>
          <h2>Why LPs use Unight.</h2>
          <div className="owners-grid">
            <div className="owners-copy glass">
              <h3>Put idle liquidity to work.</h3>
              <p>When a concentrated-liquidity position moves fully out of range, its principal becomes a single token. Unight lets you lend a bounded portion of that idle token while keeping the position in place.</p>
              <ul className="check">
                <li>Inventory follows whichever valid path consumes it first — Uniswap reactivation or Midnight lending.</li>
                <li>Shared capacity between modes, enforced onchain, never double-sold.</li>
                <li>Just-in-time funding through a Midnight buy callback.</li>
                <li>A policy-controlled Unight Account custodies the transferred position NFT.</li>
              </ul>
            </div>
            <div className="owners-balance glass">
              <span className="chip">Lending venue</span>
              <div className="balance-row"><span>Capital source</span><b>Uniswap v4 position</b></div>
              <div className="balance-row"><span>Fixed-maturity venue</span><b>Morpho Midnight</b></div>
              <div className="balance-row"><span>Initial loan token</span><b>USDC</b></div>
              <div className="balance-row"><span>Chain</span><b>Base · 8453</b></div>
              <div className="balance-row"><span>Available to lend</span><b className="gold-text">{money(available)}</b></div>
              <div className="balance-row"><span>Policy-controlled</span><b>Shared capacity</b></div>
            </div>
          </div>
        </section>

        <section className="faq" id="faq">
          <span className="eyebrow">05 — Questions</span>
          <h2>FAQs</h2>
          <div className="faq-list">
            {faq.map(([q, a], i) => (
              <div className={open === i ? 'faq-item open' : 'faq-item'} key={q}>
                <button className="faq-q" onClick={() => setOpen(open === i ? null : i)}>
                  <span className="faq-num">{String(i + 1).padStart(2, '0')}</span>
                  <span className="faq-title">{q}</span>
                  <span className="faq-tgl">+</span>
                </button>
                {open === i && <p className="faq-a">{a}</p>}
              </div>
            ))}
          </div>
        </section>
      </main>

      <footer className="foot">
        <div className="foot-grid">
          <div className="foot-brand">
            <a className="brand ondark" href="#top"><Logo size={30} /><span>unight<span className="brand-dot">.</span>finance</span></a>
            <p>Conditional fixed-rate lending for out-of-range Uniswap v4 liquidity on Morpho Midnight.</p>
          </div>
          <div className="foot-cols">
            <div className="foot-col"><span className="foot-h">Explore</span><a href="#offers">Offers</a><a href="#how">How it works</a><a href="#simulator">Simulator</a><a href="#faq">FAQ</a></div>
            <div className="foot-col"><span className="foot-h">Protocol</span><a href="#simulator">Account {params.account}</a><a href="#simulator">Market {params.market} · {params.marketId}</a><a href="#simulator">Fork block {params.forkBlock}</a></div>
          </div>
        </div>
        <div className="foot-legal">
          <span>Unight is a development prototype. Not audited. Do not deposit funds.</span>
          <span>© 2026 Unight</span>
        </div>
      </footer>
    </div>
  )
}

function Stat({ label, value, detail, gold }: { label: string; value: string; detail: string; gold?: boolean }) {
  return <div className="stat"><span>{label}</span><strong className={gold ? 'gold-text' : ''}>{value}</strong><small>{detail}</small></div>
}

createRoot(document.getElementById('root')!).render(<StrictMode><App /></StrictMode>)
