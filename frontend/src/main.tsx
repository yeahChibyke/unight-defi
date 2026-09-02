import { StrictMode, useMemo, useState } from 'react'
import { createRoot } from 'react-dom/client'
import './styles.css'

const params = { tick: -64451, lower: -70790, upper: -56920, terminal: 124850, globalCap: 1000000, autoCap: 600000, bidCap: 400000, reserve: 100000, maturity: '25 Sep 2026', market: 'USDC / cbBTC', marketId: '0x549c…f221' }
type Mode = 'auto' | 'bid'

function money(n:number) { return '$' + n.toLocaleString('en-US', { maximumFractionDigits: 0 }) }
function App() {
  const [mode, setMode] = useState<Mode>('auto')
  const [amount, setAmount] = useState(40000)
  const [rate, setRate] = useState(8.5)
  const [settled, setSettled] = useState(false)
  const cap = mode === 'auto' ? params.autoCap : params.bidCap
  const available = Math.min(cap, params.terminal - params.reserve)
  const valid = amount > 0 && amount <= available
  const progress = Math.min(100, (amount / available) * 100)
  const steps = useMemo(() => mode === 'auto' ? ['Borrower ask discovered', 'Offer ratified by Midnight', 'Unight removes exact terminal principal', 'LP receives Midnight credit'] : ['LP publishes signed bid', 'Borrower accepts the offer', 'Unight validates callback context', 'LP receives Midnight credit'], [mode])
  return <div className="app">
    <header><div className="brand"><span className="mark">◒</span><span>unight<span className="muted">.finance</span></span></div><div className="header-right"><span className="live-dot"/> SIMULATION MODE <button className="connect">Connect wallet <span>↗</span></button></div></header>
    <main>
      <section className="hero"><div><div className="eyebrow">CONDITIONAL FIXED-RATE LENDING</div><h1>Make dormant liquidity<br/><em>work overnight.</em></h1><p className="lede">Unight turns safely dormant Uniswap v4 liquidity into bounded, fixed-maturity credit exposure — without moving the LP position.</p></div><div className="hero-orb"><div className="orb-ring ring-a"/><div className="orb-ring ring-b"/><span>UNIGHT<br/><small>BASE · 8453</small></span></div></section>
      <section className="stats"><Stat label="POOL TICK" value={params.tick.toLocaleString()} detail="Outside LP range"/><Stat label="TERMINAL PRINCIPAL" value={money(params.terminal)} detail="USDC · live estimate"/><Stat label="AVAILABLE TO LEND" value={money(available)} detail="After reactivation reserve"/><Stat label="MATURITY" value={params.maturity} detail="Midnight market"/></section>
      <div className="grid"><section className="panel flow-panel"><div className="panel-head"><div><div className="eyebrow">LIVE PROTOCOL FLOW</div><h2>Watch a settlement happen</h2></div><span className="badge">● PINNED FORK</span></div><div className="position"><div className="range-label"><span>cbBTC price range</span><span>{params.lower.toLocaleString()} — {params.upper.toLocaleString()}</span></div><div className="range"><i className="tick-marker" style={{left:'45%'}}/><span className="tick-text">current tick {params.tick.toLocaleString()}</span></div><div className="position-foot"><span>◈ Position #2,742,919</span><span className="green">● Dormant & eligible</span></div></div><div className="steps">{steps.map((s,i)=><div className={'step '+(settled || i===0 ? 'active':'')} key={s}><span className="step-num">{settled || i===0 ? '✓' : `0${i+1}`}</span><span>{s}</span>{i<steps.length-1&&<b>→</b>}</div>)}</div><div className={'result '+(settled?'success':'')}><span className="result-icon">{settled?'✓':'↯'}</span><div><strong>{settled?'Settlement simulated successfully':'Ready for a safe settlement'}</strong><small>{settled?`${money(amount)} USDC funded at ${rate}% fixed rate`:'Adjust the parameters, then run the flow on the right.'}</small></div></div></section>
      <section className="panel control-panel"><div className="eyebrow">INTERACTIVE SIMULATOR</div><h2>Choose a lending mode</h2><div className="tabs"><button className={mode==='auto'?'selected':''} onClick={()=>{setMode('auto');setSettled(false)}}><span>↗</span><strong>Auto-Lend</strong><small>Unight finds the borrower</small></button><button className={mode==='bid'?'selected':''} onClick={()=>{setMode('bid');setSettled(false)}}><span>⌁</span><strong>LP Bid Board</strong><small>You set the price</small></button></div><label>FUNDING AMOUNT <output>{money(amount)} USDC</output></label><input type="range" min="5000" max={available} step="5000" value={amount} onChange={e=>{setAmount(+e.target.value);setSettled(false)}}/><div className="range-values"><span>$5k</span><span>{money(available)} available</span></div><div className="capacity"><span>Mode capacity</span><span>{money(cap)} <b>{Math.round(progress)}%</b></span><div><i style={{width:`${progress}%`}}/></div></div><label>MINIMUM NET RATE <output>{rate.toFixed(1)}%</output></label><input type="range" min="0" max="20" step="0.5" value={rate} onChange={e=>setRate(+e.target.value)}/><button className="run" disabled={!valid} onClick={()=>setSettled(true)}>{mode==='auto'?'Simulate Auto-Lend':'Simulate Bid Fill'} <span>→</span></button><p className="fine">No wallet required · deterministic demo using the pinned Base block</p></section></div>
      <section className="footnote"><span>UNIGHT ACCOUNT</span><code>0xFEE7…5F24</code><span>MARKET</span><code>{params.market} · {params.marketId}</code><span>FORK BLOCK</span><code>50,000,000</code></section>
    </main><footer><span>Unight is a development prototype. Not audited. Do not deposit funds.</span><span>Read the protocol docs ↗</span></footer>
  </div>
}
function Stat({label,value,detail}:{label:string,value:string,detail:string}) { return <div className="stat"><span>{label}</span><strong>{value}</strong><small>{detail}</small></div> }
createRoot(document.getElementById('root')!).render(<StrictMode><App/></StrictMode>)
