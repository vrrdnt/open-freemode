const shell = document.querySelector('#shell');
const sidebar = document.querySelector('#sidebar');
const content = document.querySelector('#content');
const search = document.querySelector('#search');
const closeButton = document.querySelector('#close');
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'ofm_hub';

const destinations = {
  pizza: ['Pizza Delivery', 'Vinewood', '1 player', '$750', 'Five deliveries using a temporary scooter.'],
  race: ['Airport Dash', 'LSIA', '1–8 players', '$500–$1,000', 'Solo time trial or a synchronized public street race.'],
  tdm: ['Terminal Clash', 'Maze Bank Arena', '2–10 players', '$600–$1,200', 'Balanced team deathmatch to 15 kills in an isolated arena.'],
  pursuit: ['City Escape', 'Mission Row', '2–6 players', '$700–$1,500', 'One getaway driver against a team of police.'],
};

const handbook = [
  { group: 'Start here', id: 'first-hour', title: 'Your first hour', kicker: 'Start here', summary: 'A quick route from arrival to your first payout.', body: [
    'Finish creating your character, then use the shared world between structured matches. Your identity, appearance, bank balance and owned vehicles persist.',
    'Open Activities, choose a mode, and set a GPS route. Enter the marker at the destination to join. Start with Pizza Delivery if you are alone or Airport Dash if you already have a car.'
  ], steps: ['Use F7 whenever you need this handbook.', 'Complete Pizza Delivery or an Airport Dash run for your first bank payout.', 'Buy a persistent starter car at Premium Deluxe Motorsport.', 'Store it at Legion Square and modify it at Burton Customs.'] },
  { group: 'Start here', id: 'controls', title: 'Controls and keys', kicker: 'Reference', summary: 'The few controls that organize the whole server.', body: [
    'F7 opens this handbook. M opens restricted vMenu for temporary cars and weapons. F2 opens your persistent inventory. E interacts with world markers.',
    'Activity controls take priority while a match is active. Use /pizza_cancel, /race_cancel, /tdm_cancel, or /pursuit_cancel to abandon the matching mode safely.'
  ] },
  { group: 'World', id: 'money', title: 'Money and progression', kicker: 'Persistent world', summary: 'Bank funds connect activities, vehicles and apartment garages.', body: [
    'Activity rewards go to your Qbox bank account once the server validates the result. Duplicate finish events and retries do not create another payout.',
    'Vehicle purchases and modifications charge the bank on the server. Temporary vMenu equipment is free but never becomes persistent property.'
  ] },
  { group: 'World', id: 'vehicles', title: 'Owned and temporary vehicles', kicker: 'Vehicles', summary: 'Know which cars survive a restart.', body: [
    'Cars bought at Premium Deluxe Motorsport are owned by the active character. Retrieve and store them at Legion Square Garage or at an apartment garage that character has purchased; Burton Customs saves supported repairs, performance parts and colors.',
    'Cars spawned from vMenu and cars issued by activities are temporary. A copied plate cannot turn either one into an owned vehicle, and the garage rejects them.'
  ] },
  { group: 'World', id: 'properties', title: 'Apartment garages', kicker: 'Properties', summary: 'Purchase permanent private garage access for one character.', body: [
    'Alta Street and Del Perro sell persistent garage access from your bank account. Each purchase belongs to the active character and unlocks storage and retrieval at that location.',
    'These first properties provide an activated apartment garage without a housing interior. Legion Square remains available without a property purchase.'
  ] },
  { group: 'World', id: 'vendors', title: 'Supply vendors', kicker: 'Vendors', summary: 'Persistent supplies without covering the map in shop icons.', body: [
    'Four convenience stores and two AmmuNation counters sell bandages, body armor and parachutes from your bank account. Purchased items enter your persistent F2 inventory.',
    'vMenu already supplies temporary freemode weapons, so AmmuNation sells useful supplies instead of charging you for the same weapon access. Vendor purchases are unavailable during activities.'
  ] },
  { group: 'Activities', id: 'activity-lifecycle', title: 'How activities work', kicker: 'Fair play', summary: 'Queue, prepare, play, resolve, restore.', body: [
    'Every structured mode validates entry in the world, saves your freemode state, and moves players into an isolated session where required. The server owns checkpoints, score, timing and payouts.',
    'Finishing, cancelling, dying, disconnecting, unloading a character or restarting a resource all follow cleanup paths designed to remove temporary equipment and return you to freemode.'
  ] },
  { group: 'Activities', id: 'racing', title: 'Racing', kicker: 'Airport Dash', summary: 'Solo records and public grid starts.', body: [
    'Drive into the LSIA marker as the driver. Solo mode records your best elapsed time. Public mode queues 2–8 drivers, places them on an ordered grid and briefly ghosts cars at launch.',
    'Pass every checkpoint in order with the same vehicle. First through third in public racing receive $1,000, $750 and $600; later finishers receive $500.'
  ] },
  { group: 'Activities', id: 'combat', title: 'TDM and City Escape', kicker: 'Combat', summary: 'Temporary loadouts with isolated scoring.', body: [
    'Terminal Clash balances 2–10 players into red and blue teams. Enemy kills score; suicides and friendly kills do not. The first team to 15 wins.',
    'City Escape assigns the first queued player as robber. Reach five checkpoints in the Sultan before police stop the driver, destroy the car or run out the five-minute clock.'
  ] },
  { group: 'Help', id: 'recovery', title: 'Recovery and common issues', kicker: 'Help', summary: 'What to do when a route or vehicle is interrupted.', body: [
    'If an owned car was out when the server restarted, visit Legion Square Garage and use its Recoverable entry. The garage prevents a second copy while the real entity is still present.',
    'Use the activity cancel command before starting something else. Freemode death recovery returns you to LSIA after five seconds. If a menu remains open unexpectedly, press Escape once before reconnecting.'
  ] },
];

let state = { page: 'handbook', article: 'first-hour', onboarding: false, slide: 0, playerName: 'Player' };

const post = async (name, data = {}) => {
  try { await fetch(`https://${resource}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) }); } catch (_) {}
};

const el = (tag, className, text) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
};

function setPage(page) {
  state.page = page;
  state.onboarding = false;
  search.value = '';
  render();
}

function renderSidebar(items = handbook) {
  sidebar.replaceChildren();
  let group;
  for (const item of items) {
    if (item.group !== group) {
      group = item.group;
      sidebar.append(el('div', 'side-label', group));
    }
    const button = el('button', `side-button${state.article === item.id ? ' active' : ''}`, item.title);
    button.addEventListener('click', () => { state.article = item.id; state.page = 'handbook'; render(); });
    sidebar.append(button);
  }
}

function renderArticle(item) {
  content.replaceChildren();
  content.append(el('div', 'eyebrow', item.kicker), el('h1', '', item.title), el('div', 'rule'), el('p', 'lead', item.summary));
  for (const paragraph of item.body) content.append(el('p', '', paragraph));
  if (item.steps) {
    const list = el('ol', 'steps');
    item.steps.forEach(step => list.append(el('li', '', step)));
    content.append(list);
  }
}

function waypointButton(id, label = 'Set waypoint', complete = false) {
  const button = el('button', 'primary', label);
  button.addEventListener('click', () => post('waypoint', { id, complete }));
  return button;
}

function renderActivities() {
  sidebar.replaceChildren();
  sidebar.append(el('div', 'side-label', 'Play now'));
  Object.entries(destinations).forEach(([id, details]) => {
    const button = el('button', 'side-button', details[0]);
    button.addEventListener('click', () => document.querySelector(`[data-activity="${id}"]`)?.scrollIntoView({ behavior: 'smooth' }));
    sidebar.append(button);
  });
  content.replaceChildren(el('div', 'eyebrow', 'Activity network'), el('h1', '', 'Choose your next run'), el('div', 'rule'),
    el('p', 'lead', 'Set a route, travel there in the shared world, and enter the marker. The destination validates your queue entry on the server.'));
  const grid = el('div', 'cards');
  for (const [id, [title, place, players, payout, description]] of Object.entries(destinations)) {
    const card = el('article', 'card');
    card.dataset.activity = id;
    card.append(el('div', 'tag', 'Available'), el('h2', '', title), el('p', '', description));
    const meta = el('div', 'meta');
    [place, players, payout].forEach(value => meta.append(el('span', '', value)));
    card.append(meta, waypointButton(id));
    grid.append(card);
  }
  content.append(grid);
}

const slides = [
  ['Welcome to Open Freemode', 'A shared Los Santos built around fast access to racing, combat, pursuits and delivery work.', 'Your character, appearance, money, inventory and purchased cars persist. The free cars and weapons in vMenu are there for casual freemode play.'],
  ['One world, four activities', 'Use the activity browser to set a GPS route. Entry still happens at a real destination in the world.', 'The server validates teams, vehicles, checkpoints, scores and rewards. When a mode ends, its temporary rules and equipment are removed before you return.'],
  ['Build your world', 'Activity payouts fund persistent supplies, cars, upgrades and private garage access.', 'Buy supplies at focused world vendors and a starter vehicle at Premium Deluxe Motorsport. Alta Street and Del Perro offer purchasable apartment garages. vMenu assets stay temporary.'],
];

function renderWelcome() {
  sidebar.replaceChildren(el('div', 'side-label', `Orientation ${state.slide + 1} / ${slides.length}`));
  slides.forEach((slide, index) => {
    const button = el('button', `side-button${state.slide === index ? ' active' : ''}`, slide[0]);
    button.addEventListener('click', () => { state.slide = index; renderWelcome(); });
    sidebar.append(button);
  });
  const [title, lead, body] = slides[state.slide];
  content.replaceChildren(el('div', 'eyebrow', `Welcome, ${state.playerName}`), el('h1', '', title), el('div', 'rule'), el('p', 'lead', lead), el('p', '', body));
  if (state.slide === 1) {
    const grid = el('div', 'cards');
    Object.values(destinations).forEach(([name, , players]) => {
      const card = el('div', 'card'); card.append(el('div', 'tag', players), el('h2', '', name)); grid.append(card);
    });
    content.append(grid);
  }
  const actions = el('div', 'onboard-actions');
  if (state.slide > 0) {
    const back = el('button', 'secondary', 'Back'); back.addEventListener('click', () => { state.slide--; renderWelcome(); }); actions.append(back);
  }
  if (state.slide < slides.length - 1) {
    const next = el('button', 'primary', 'Continue'); next.addEventListener('click', () => { state.slide++; renderWelcome(); }); actions.append(next);
  } else {
    const finish = el('button', 'primary', 'Enter Los Santos'); finish.addEventListener('click', () => post('close', { complete: true })); actions.append(finish);
    const route = waypointButton('pizza', 'Route to first job', true); actions.append(route);
  }
  content.append(actions);
}

function renderSearch(query) {
  const normalized = query.trim().toLowerCase();
  if (!normalized) { state.page = 'handbook'; return render(); }
  state.page = 'search';
  const matches = handbook.filter(item => [item.title, item.summary, ...item.body, ...(item.steps || [])].join(' ').toLowerCase().includes(normalized));
  renderSidebar(matches);
  content.replaceChildren(el('div', 'eyebrow', 'Search'), el('h1', '', `${matches.length} result${matches.length === 1 ? '' : 's'}`), el('div', 'rule'));
  if (!matches.length) return content.append(el('div', 'empty', 'No handbook page matches that search.'));
  const grid = el('div', 'cards');
  matches.forEach(item => {
    const card = el('button', 'card');
    card.style.textAlign = 'left'; card.style.color = 'inherit'; card.style.cursor = 'pointer';
    card.append(el('div', 'tag', item.group), el('h2', '', item.title), el('p', '', item.summary));
    card.addEventListener('click', () => { search.value = ''; state.article = item.id; state.page = 'handbook'; render(); });
    grid.append(card);
  });
  content.append(grid);
}

function render() {
  document.querySelectorAll('.tabs button').forEach(button => button.classList.toggle('active', button.dataset.page === state.page));
  if (state.page === 'welcome' || state.onboarding) return renderWelcome();
  if (state.page === 'activities') return renderActivities();
  const item = handbook.find(entry => entry.id === state.article) || handbook[0];
  state.article = item.id;
  renderSidebar();
  renderArticle(item);
  content.scrollTop = 0;
}

window.addEventListener('message', event => {
  const data = event.data || {};
  if (data.action === 'open') {
    state = { page: data.onboarding ? 'welcome' : (data.page || 'handbook'), article: 'first-hour', onboarding: data.onboarding === true, slide: 0, playerName: data.playerName || 'Player' };
    shell.classList.add('visible'); shell.setAttribute('aria-hidden', 'false');
    render(); setTimeout(() => (state.onboarding ? content : search).focus(), 0);
  } else if (data.action === 'close') {
    shell.classList.remove('visible'); shell.setAttribute('aria-hidden', 'true');
  }
});

document.querySelectorAll('.tabs button').forEach(button => button.addEventListener('click', () => setPage(button.dataset.page)));
closeButton.addEventListener('click', () => post('close'));
search.addEventListener('input', event => renderSearch(event.target.value));
document.addEventListener('keydown', event => { if (event.key === 'Escape' && shell.classList.contains('visible')) post('close'); });

if (location.hostname === '127.0.0.1' || location.hostname === 'localhost') {
  document.body.classList.add('preview');
  window.postMessage({ action: 'open', onboarding: true, playerName: 'Franklin' }, '*');
}
