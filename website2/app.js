// =============================================
// ЇжGo Website — Main Script
// =============================================

const SUPABASE_URL = 'https://ixdjtrixddggmermdbgv.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml4ZGp0cml4ZGRnZ21lcm1kYmd2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE0OTg5NTAsImV4cCI6MjA4NzA3NDk1MH0.-FR97XKTuYoueC91MUvMd5Int4EPfaX6mTd-GyON0tQ';

const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ===== HEADER =====
const header = document.getElementById('header');
const burger = document.getElementById('burger');
const nav = document.getElementById('nav');

window.addEventListener('scroll', () => {
  header.classList.toggle('scrolled', window.scrollY > 40);
});

burger.addEventListener('click', () => {
  nav.classList.toggle('open');
});

nav.querySelectorAll('a').forEach(a => {
  a.addEventListener('click', () => nav.classList.remove('open'));
});

// ===== SCROLL ANIMATIONS =====
const fadeEls = document.querySelectorAll('.adv-card, .section-title');
const fadeObserver = new IntersectionObserver((entries) => {
  entries.forEach(e => {
    if (e.isIntersecting) { e.target.classList.add('visible'); }
  });
}, { threshold: 0.15 });

fadeEls.forEach(el => {
  el.classList.add('fade-up');
  fadeObserver.observe(el);
});

// ===== RESTAURANTS =====
let restaurantsData = [];

async function loadRestaurants() {
  const grid = document.getElementById('restGrid');
  try {
    const { data, error } = await sb
      .from('restaurants')
      .select('*')
      .order('name');

    if (error) throw error;
    if (!data || data.length === 0) {
      grid.innerHTML = '<div class="rest-loading">Ресторани скоро з\'являться</div>';
      return;
    }

    restaurantsData = data;

    grid.innerHTML = data.map(r => {
      const isOpen = checkIsOpen(r);
      const statusClass = isOpen ? 'rest-card__badge--open' : 'rest-card__badge--closed';
      const statusText = isOpen ? 'Відчинено' : 'Зачинено';
      const hours = `${r.open_time || '10:00'} - ${r.close_time || '22:00'}`;
      const rating = r.rating || '5.0';
      const time = r.time || '30 хв';

      return `
        <div class="rest-card fade-up visible" onclick="openRestModal('${r.id}')">
          ${r.image_url
            ? `<img class="rest-card__img" src="${r.image_url}" alt="${r.name}" loading="lazy">`
            : `<div class="rest-card__img-placeholder">&#127869;</div>`
          }
          <span class="rest-card__badge ${statusClass}">${statusText}</span>
          ${r.is_peak_hours ? '<span class="rest-card__badge rest-card__badge--peak" style="right:auto;left:12px">&#128293; Навантаження</span>' : ''}
          <div class="rest-card__body">
            <div class="rest-card__name">${r.name}</div>
            <div class="rest-card__meta">
              <span>&#9201; ${hours}</span>
              <span>&#11088; ${rating}</span>
              <span>&#128666; ${time}</span>
            </div>
          </div>
        </div>
      `;
    }).join('');

  } catch (err) {
    console.error('Error loading restaurants:', err);
    grid.innerHTML = '<div class="rest-loading">Помилка завантаження</div>';
  }
}

function checkIsOpen(r) {
  if (r.is_open === false) return false;
  if (!r.open_time || !r.close_time) return true;

  const now = new Date();
  const [oh, om] = r.open_time.split(':').map(Number);
  const [ch, cm] = r.close_time.split(':').map(Number);
  const minutes = now.getHours() * 60 + now.getMinutes();
  const openMin = oh * 60 + om;
  const closeMin = ch * 60 + cm;

  if (closeMin > openMin) {
    return minutes >= openMin && minutes < closeMin;
  } else {
    // Overnight (e.g., 22:00 - 06:00)
    return minutes >= openMin || minutes < closeMin;
  }
}

// ===== RESTAURANT MODAL =====
const modalOverlay = document.getElementById('restModal');
const modalClose = document.getElementById('modalClose');

modalClose.addEventListener('click', closeModal);
modalOverlay.addEventListener('click', (e) => {
  if (e.target === modalOverlay) closeModal();
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closeModal();
});

function closeModal() {
  modalOverlay.classList.remove('active');
  document.body.style.overflow = '';
}

async function openRestModal(id) {
  const r = restaurantsData.find(x => String(x.id) === String(id));
  if (!r) return;

  const isOpen = checkIsOpen(r);

  document.getElementById('modalName').textContent = r.name;
  document.getElementById('modalHours').textContent = `&#9201; ${r.open_time || '10:00'} - ${r.close_time || '22:00'}`;
  document.getElementById('modalHours').innerHTML = `&#9201; ${r.open_time || '10:00'} - ${r.close_time || '22:00'}`;
  document.getElementById('modalRating').innerHTML = `&#11088; ${r.rating || '5.0'}`;

  const statusEl = document.getElementById('modalStatus');
  statusEl.textContent = isOpen ? 'Відчинено' : 'Зачинено';
  statusEl.className = 'modal__badge ' + (isOpen ? 'rest-card__badge--open' : 'rest-card__badge--closed');

  const imgEl = document.getElementById('modalImg');
  if (r.image_url) {
    imgEl.src = r.image_url;
    imgEl.style.display = 'block';
  } else {
    imgEl.style.display = 'none';
  }

  // Load dish categories for this restaurant
  const catsEl = document.getElementById('modalCats');
  catsEl.innerHTML = '<span style="color:var(--text3)">Завантаження...</span>';

  try {
    const { data: dishes } = await sb
      .from('dishes')
      .select('category, section')
      .eq('restaurant_id', id);

    if (dishes && dishes.length > 0) {
      const uniqueCats = [...new Map(dishes.map(d => [d.category, d])).values()];
      catsEl.innerHTML = uniqueCats.map(d =>
        `<span class="modal__cat">${d.category}</span>`
      ).join('');
    } else {
      catsEl.innerHTML = '<span style="color:var(--text3)">Меню ще формується</span>';
    }
  } catch {
    catsEl.innerHTML = '<span style="color:var(--text3)">Помилка завантаження</span>';
  }

  modalOverlay.classList.add('active');
  document.body.style.overflow = 'hidden';
}

// ===== CONTACTS =====
// Editable contacts — stored in localStorage for admin, with fallbacks
function loadContacts() {
  const grid = document.getElementById('contactsGrid');
  const saved = localStorage.getItem('izhgo_contacts');
  let contacts;

  if (saved) {
    try { contacts = JSON.parse(saved); } catch { contacts = null; }
  }

  if (!contacts) {
    contacts = [
      { icon: '&#128222;', label: 'Телефон', value: '+38 (050) 123-45-67', href: 'tel:+380501234567' },
      { icon: '&#128172;', label: 'Telegram', value: '@izhgo_support', href: 'https://t.me/izhgo_support' },
      { icon: '&#128231;', label: 'Email', value: 'info@izhgo.com.ua', href: 'mailto:info@izhgo.com.ua' },
    ];
    localStorage.setItem('izhgo_contacts', JSON.stringify(contacts));
  }

  grid.innerHTML = contacts.map(c => `
    <a href="${c.href}" class="contact-card" target="_blank" rel="noopener">
      <div class="contact-card__icon">${c.icon}</div>
      <div class="contact-card__info">
        <small>${c.label}</small>
        <strong>${c.value}</strong>
      </div>
    </a>
  `).join('');

  // Admin edit button (tiny, bottom-right)
  grid.innerHTML += `
    <button onclick="editContacts()" style="position:fixed;bottom:16px;right:16px;background:var(--card);border:1px solid var(--border);color:var(--text3);width:36px;height:36px;border-radius:50%;cursor:pointer;font-size:.9rem;z-index:50;display:flex;align-items:center;justify-content:center;" title="Редагувати контакти">&#9998;</button>
  `;
}

function editContacts() {
  const saved = localStorage.getItem('izhgo_contacts');
  let contacts = saved ? JSON.parse(saved) : [];

  let html = '<div style="position:fixed;inset:0;background:rgba(0,0,0,.7);z-index:300;display:flex;align-items:center;justify-content:center;padding:20px" id="contactEditor">';
  html += '<div style="background:var(--card);border-radius:var(--r-lg);padding:28px;max-width:500px;width:100%;max-height:80vh;overflow-y:auto">';
  html += '<h3 style="color:var(--white);margin-bottom:16px">Редагувати контакти</h3>';

  contacts.forEach((c, i) => {
    html += `
      <div style="background:var(--bg2);border-radius:12px;padding:14px;margin-bottom:12px;display:flex;gap:8px;align-items:end">
        <div style="flex:1">
          <label style="font-size:.7rem;color:var(--text3);display:block">Емодзі</label>
          <input id="ci_${i}" value="${c.icon.replace(/&/g,'&amp;').replace(/"/g,'&quot;')}" style="width:100%;padding:6px 10px;background:var(--bg);border:1px solid var(--border);border-radius:8px;color:var(--white);font-size:.9rem">
        </div>
        <div style="flex:1">
          <label style="font-size:.7rem;color:var(--text3);display:block">Назва</label>
          <input id="cl_${i}" value="${c.label}" style="width:100%;padding:6px 10px;background:var(--bg);border:1px solid var(--border);border-radius:8px;color:var(--white);font-size:.9rem">
        </div>
        <div style="flex:2">
          <label style="font-size:.7rem;color:var(--text3);display:block">Значення</label>
          <input id="cv_${i}" value="${c.value}" style="width:100%;padding:6px 10px;background:var(--bg);border:1px solid var(--border);border-radius:8px;color:var(--white);font-size:.9rem">
        </div>
        <div style="flex:2">
          <label style="font-size:.7rem;color:var(--text3);display:block">Посилання</label>
          <input id="ch_${i}" value="${c.href}" style="width:100%;padding:6px 10px;background:var(--bg);border:1px solid var(--border);border-radius:8px;color:var(--white);font-size:.9rem">
        </div>
        <button onclick="removeContact(${i})" style="background:rgba(239,68,68,.15);border:none;color:var(--red);width:32px;height:32px;border-radius:8px;cursor:pointer;font-size:1.1rem;flex-shrink:0">&times;</button>
      </div>
    `;
  });

  html += `<div style="display:flex;gap:10px;margin-top:16px">
    <button onclick="addContact()" style="flex:1;padding:10px;background:var(--bg);border:1px solid var(--border);border-radius:12px;color:var(--accent);font-weight:700;cursor:pointer;font-family:'Montserrat',sans-serif">+ Додати</button>
    <button onclick="saveContacts(${contacts.length})" style="flex:1;padding:10px;background:var(--accent);border:none;border-radius:12px;color:#000;font-weight:700;cursor:pointer;font-family:'Montserrat',sans-serif">Зберегти</button>
    <button onclick="document.getElementById('contactEditor').remove()" style="flex:1;padding:10px;background:var(--bg);border:1px solid var(--border);border-radius:12px;color:var(--text2);font-weight:700;cursor:pointer;font-family:'Montserrat',sans-serif">Скасувати</button>
  </div>`;
  html += '</div></div>';

  document.body.insertAdjacentHTML('beforeend', html);
}

function addContact() {
  const saved = localStorage.getItem('izhgo_contacts');
  let contacts = saved ? JSON.parse(saved) : [];
  contacts.push({ icon: '&#128222;', label: 'Новий', value: '', href: '' });
  localStorage.setItem('izhgo_contacts', JSON.stringify(contacts));
  document.getElementById('contactEditor').remove();
  editContacts();
}

function removeContact(idx) {
  const saved = localStorage.getItem('izhgo_contacts');
  let contacts = saved ? JSON.parse(saved) : [];
  contacts.splice(idx, 1);
  localStorage.setItem('izhgo_contacts', JSON.stringify(contacts));
  document.getElementById('contactEditor').remove();
  editContacts();
}

function saveContacts(count) {
  const contacts = [];
  for (let i = 0; i < count; i++) {
    const iconEl = document.getElementById(`ci_${i}`);
    if (!iconEl) continue;
    contacts.push({
      icon: iconEl.value,
      label: document.getElementById(`cl_${i}`).value,
      value: document.getElementById(`cv_${i}`).value,
      href: document.getElementById(`ch_${i}`).value,
    });
  }
  localStorage.setItem('izhgo_contacts', JSON.stringify(contacts));
  document.getElementById('contactEditor').remove();
  loadContacts();
}

// ===== INIT =====
loadRestaurants();
loadContacts();
