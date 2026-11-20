(() => {
  'use strict';
  const paths = {
    close: '<path d="m6 6 12 12M18 6 6 18"/>',
    back: '<path d="m14 5-7 7 7 7"/>',
    arrow: '<path d="M5 12h14m-6-6 6 6-6 6"/>',
    chevron: '<path d="m9 5 7 7-7 7"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    heart: '<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"/>',
    wifi: '<path d="M3 8a15 15 0 0 1 18 0M6 12a10 10 0 0 1 12 0m-9 4a5 5 0 0 1 6 0"/><circle cx="12" cy="20" r=".5"/>',
    signal: '<path d="M4 18v-4m5 4v-7m5 7V8m5 10V5" stroke-width="3"/>',
    battery: '<rect x="2" y="7" width="17" height="10" rx="2"/><path d="M22 10v4"/><path d="M5 10h11v4H5Z" fill="currentColor" stroke="none"/>',
    download: '<path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/>',
    play: '<path d="m8 4 12 8-12 8Z" fill="currentColor" stroke="none"/>',
    pause: '<path d="M8 5v14m8-14v14" stroke-width="3"/>',
    layers: '<path d="m12 3 10 5-10 5L2 8Zm-9 10 9 5 9-5M3 18l9 5 9-5"/>',
    shield: '<path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6Z"/><path d="m8 12 3 3 5-6"/>',
    folder: '<path d="M3 6h7l2 3h9v11H3Z"/>',
    more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    captions: '<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M7 10h2m-2 4h3m4-4h3m-3 4h3"/>',
    volume: '<path d="m11 4-6 5H2v6h3l6 5Zm4 4a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>',
    expand: '<path d="M3 9V3h6m6 0h6v6m0 6v6h-6m-6 0H3v-6"/>',
    sort: '<path d="M8 4v16m-4-4 4 4 4-4m5-12v16m-4-12 4-4 4 4"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10v.1"/>',
    trash: '<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7"/>',
    bars: '<path d="M5 10v4m5-9v14m5-12v10m5-6v2"/>',
    chat: '<path d="M4 4h16v12H9l-5 4Z"/><path d="M7 8h10m-10 4h6"/>'
  };
  const icon = name => `<svg class="ico" viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.more}</svg>`;
  const concepts = [
    {id:'a',name:'原生轻盈',kicker:'NATIVE & QUIET',caption:'系统分组与小封面，让缓存入口自然融入现有 App。操作集中在底部，轻、稳、熟悉。'},
    {id:'b',name:'封面画廊',kicker:'COVERS FIRST',caption:'用封面组织内容，保留更舒展的阅读节奏。适合把离线缓存当作一份随身片单。'},
    {id:'c',name:'紧凑清单',kicker:'EVERYTHING IN ORDER',caption:'缩短标题区、收紧行距，集中呈现空间和任务状态。适合多 P 与大量下载管理。'},
    {id:'d',name:'暗色影院',kicker:'READY TO PLAY',caption:'深色底、沉浸封面与柔和紫色控件。打开缓存之后，视觉重心直接落在播放内容上。'}
  ];
  const media = [
    {id:0,title:'把周末交给山野',author:'山野来信',cover:'mountain',duration:'3 集',meta:'3 集 · 1080P',size:1260,count:3},
    {id:1,title:'我把桌面重新整理了一遍',author:'小岛工作室',cover:'desk',duration:'18:42',meta:'1080P · 386 MB',size:386,count:1},
    {id:2,title:'下雨天，去东京散个步',author:'慢一点生活',cover:'city',duration:'24:08',meta:'1080P · 482 MB',size:482,count:1},
    {id:3,title:'写代码时的安静角落',author:'声音博物馆',cover:'quiet',duration:'42:16',meta:'720P · 296 MB',size:296,count:1}
  ];
  const episodes = [
    {title:'山脚下的第一缕晨光',duration:'12:36',size:286},
    {title:'沿着山脊，慢慢走',duration:'16:28',size:392},
    {title:'在日落之前抵达',duration:'14:52',size:335},
    {title:'把时间留给星空',duration:'11:09',size:251}
  ];
  const state = Object.fromEntries(concepts.map(c => [c.id, freshState()]));
  let currentStage = 'library', view = 'compare', focus = 'a', favorites = new Set();
  const area = document.getElementById('concepts');
  const notes = document.getElementById('review-comment');
  try { const saved = JSON.parse(localStorage.getItem('neobili-offline-design-review') || '{}'); favorites = new Set((saved.favorites || []).filter(id => state[id])); notes.value = saved.notes || ''; } catch {}
  function freshState() {
    return {stage:'library',quality:'1080P',scope:'parts',selected:new Set([1]),editing:false,marked:new Set(),deleted:new Set(),modal:null,playing:false,position:504,language:'中文',danmaku:true,speed:1,video:0,episode:1,reverse:false,tasks:[
      {id:0,title:'P3 · 在日落之前抵达',cover:'mountain',quality:'1080P',progress:68,status:'active',size:335},
      {id:1,title:'我把桌面重新整理了一遍',cover:'desk',quality:'1080P',progress:0,status:'wifi',size:386},
      {id:2,title:'下雨天，去东京散个步',cover:'city',quality:'1080P',progress:96,status:'failed',size:482}
    ]};
  }
  function action(name, label, cls = '', extra = '') { return `<button type="button" class="${cls}" data-action="${name}" ${extra}>${label}</button>`; }
  function check(on) { return `<span class="check ${on ? 'on' : ''}">${icon('check')}</span>`; }
  function cover(item) { return `<div class="cover"><img src="assets/${item.cover}.svg" alt="${item.title}" draggable="false"><span class="cover-time">${item.duration}</span></div>`; }
  function storage(s) {
    const size = media.filter(m => !s.deleted.has(m.id)).reduce((n,m) => n + m.size,0);
    return `<div class="storage"><div class="storage-line"><span><strong>${(size / 1000).toFixed(1)} GB</strong> 已缓存</span><span>可用 ${(21.024 - size / 1000).toFixed(1)} GB</span></div><div class="storage-track"><span style="width:${Math.max(0,size / 210.24)}%"></span></div></div>`;
  }
  function appTabs(s) { return `<div class="app-tabs">${action('library','已缓存',s.stage === 'library' ? 'active' : '')}${action('downloads',`下载中 <span>${s.tasks.length}</span>`,s.stage === 'downloads' ? 'active' : '')}</div>`; }
  function head(id,s) {
    const count = media.filter(m => !s.deleted.has(m.id)).reduce((n,m) => n + m.count,0);
    return `<header class="phone-head"><div class="utility">${action('exit',icon('back'),'icon-btn','aria-label="返回我的服务"')}${action('edit',s.editing ? '完成' : '管理','text-btn')}</div><div class="head-row"><h2>离线缓存</h2>${id === 'c' ? icon('folder') : ''}</div><p class="head-caption">${id === 'b' ? '留给路上的好时光' : id === 'd' ? '好内容，随时开场。' : `${count} 个视频，随时可以观看`}</p>${storage(s)}${appTabs(s)}</header>`;
  }
  function library(id,s) {
    const available = media.filter(m => !s.deleted.has(m.id));
    if (s.reverse) available.reverse();
    const className = id === 'b' ? 'gallery' : id === 'c' ? 'compact media-list' : id === 'd' ? 'cinema-list' : 'media-list';
    const cards = available.map((m,i) => action('open',`${s.editing ? check(s.marked.has(m.id)) : ''}${cover(m)}<div class="media-copy"><h3>${m.title}</h3><p class="author">${m.author}</p><p>${m.meta}</p>${m.count > 1 ? `<span class="collection-badge">${icon('layers')} 合集 · 查看选集</span>` : ''}</div>${id === 'c' ? icon('chevron') : ''}`,`media-card ${i === 0 && m.id === 0 ? 'featured' : ''}`,`data-id="${m.id}" aria-label="${s.editing ? '选择' : '打开'}${m.title}"`)).join('');
    return `${head(id,s)}<div class="scroll ${s.editing ? 'editing' : ''}">${id === 'c' ? `<div class="list-toolbar"><span>名称 / 画质 / 大小</span>${action('sort',`最近缓存 ${icon('sort')}`)}</div>` : id === 'a' ? '<div class="section-title"><h3>我的离线片单</h3><span>全部已就绪</span></div>' : ''}<div class="${className}">${cards || '<div class="empty-state">还没有缓存内容</div>'}</div>${id === 'c' ? `<div class="compact-info"><div><b>${available.reduce((n,m)=>n+m.count,0)}</b><span>个视频</span></div><div><b>${available.filter(m=>m.count>1).length}</b><span>个合集</span></div><div><b>${(available.reduce((n,m)=>n+m.size,0)/1000).toFixed(1)} GB</b><span>本地占用</span></div></div>` : ''}<div class="library-note">${icon('shield')} 视频、弹幕和字幕均已保存</div></div>${s.editing ? `<div class="bottom-action">${action('delete',`${icon('trash')} 删除所选（${s.marked.size}）`,'primary-btn delete-btn',s.marked.size ? '' : 'disabled')}</div>` : ''}`;
  }
  function selection(id,s) {
    const chosen = [...s.selected];
    const size = chosen.reduce((n,i) => n + episodes[i].size,0) * (s.quality === '4K' ? 2.7 : s.quality === '720P' ? .62 : 1);
    const rows = episodes.map((ep,i) => action('episode',`<span class="episode-number">${String(i+1).padStart(2,'0')}</span><div class="episode-copy"><h3>${ep.title}${i === 1 ? '<span class="tiny-tag">当前</span>' : ''}</h3><p>${ep.duration} · ${s.scope === 'collection' ? '山野周记' : `P${i+1}`}</p></div>${check(s.selected.has(i))}`,`episode ${s.selected.has(i) ? 'selected' : ''}`,`data-index="${i}" aria-pressed="${s.selected.has(i)}"`)).join('');
    return `<header class="phone-head"><div class="sheet-grabber"></div><div class="head-row">${action('library','取消','text-btn')}<h2>缓存视频</h2><span style="width:7cqw"></span></div></header><div class="scroll"><div class="selection-header"><img src="assets/mountain.svg" alt="山间徒步封面"><div><h3>把周末交给山野</h3><p>山野来信 · 4 个分 P</p></div></div><div class="quality-label">缓存画质</div><div class="quality-options">${['720P','1080P','4K'].map(q=>action('quality',q,q === s.quality ? 'active' : '',`data-value="${q}" aria-pressed="${q === s.quality}"`)).join('')}</div><div class="quality-hint">同时保存弹幕和全部字幕 · 默认仅 Wi-Fi</div><div class="scope-switch">${action('scope','当前视频',s.scope === 'parts' ? 'active' : '','data-value="parts"')}${action('scope','UP 主合集',s.scope === 'collection' ? 'active' : '','data-value="collection"')}</div><div class="section-title"><h3>选择${s.scope === 'collection' ? '合集视频' : '分 P'}</h3>${action('all',s.selected.size === episodes.length ? '取消全选' : '全选','text-btn')}</div><div class="episodes">${rows}</div></div><div class="bottom-action"><div class="bottom-meta"><span>已选 <strong>${chosen.length}</strong> 项</span><span>预计 <strong>${size > 1000 ? `${(size/1000).toFixed(2)} GB` : `${Math.round(size)} MB`}</strong></span></div>${action('start',`${icon('download')} 开始缓存`,'primary-btn',chosen.length ? '' : 'disabled')}</div>`;
  }
  function taskCard(t) {
    const active = t.status === 'active', paused = t.status === 'paused', wifi = t.status === 'wifi';
    const label = active ? (t.progress === 96 ? '正在补全字幕' : '正在下载') : paused ? '已暂停' : wifi ? '等待 Wi-Fi' : '字幕下载失败';
    return `<div class="download-card"><div class="task-top"><img src="assets/${t.cover}.svg" alt=""><div class="task-title"><h3>${t.title}</h3><p>${t.quality} · ${label}</p></div>${action('task-toggle',icon(active ? 'pause' : 'play'),'round-progress',`data-id="${t.id}" aria-label="${active ? '暂停' : '继续'}${t.title}" style="background:conic-gradient(var(--tint) ${t.progress}%,var(--line) 0)"`)}</div><div class="progress-track"><div class="progress-fill" style="width:${t.progress}%"></div></div><div class="task-foot"><span>${Math.round(t.size * t.progress / 100)} / ${t.size} MB</span><strong>${active ? '4.2 MB/s' : paused ? `${t.progress}%` : ''}</strong></div>${wifi ? `<div class="task-actions"><span class="task-warning">${icon('wifi')} 仅本任务可放行</span>${action('cellular','使用蜂窝','small-action',`data-id="${t.id}"`)}</div>` : t.status === 'failed' ? `<div class="task-actions"><span class="task-warning">资源完整后进入已缓存</span>${action('retry','重试','small-action',`data-id="${t.id}"`)}</div>` : ''}<div class="task-actions">${action('task-quality','更换画质','small-action muted',`data-id="${t.id}"`)}${action('cancel-task','取消下载','small-action muted',`data-id="${t.id}"`)}</div></div>`;
  }
  function downloads(id,s) {
    return `${head(id,s)}<div class="scroll"><div class="task-summary">${icon('download')}<span>${s.tasks.filter(t=>t.status==='active').length} 项正在下载</span><strong>${s.tasks.some(t=>t.status==='active') ? '4.2 MB/s' : ''}</strong></div>${s.tasks.length ? `<div class="task-group">${s.tasks.map(taskCard).join('')}</div>` : '<div class="empty-state">暂无下载任务</div>'}<div class="offline-footnote">切到后台后继续下载。手动暂停的任务，需要手动恢复。</div></div>`;
  }
  function time(seconds) { return `${Math.floor(seconds/60).toString().padStart(2,'0')}:${(seconds%60).toString().padStart(2,'0')}`; }
  function player(id,s) {
    const m = media[s.video];
    const ep = episodes[s.episode];
    const title = s.video === 0 ? ep.title : m.title;
    const subtitle = s.language === 'English' ? 'Take your time. The mountains will wait.' : '慢一点，山会一直在这里。';
    return `<header class="phone-head"><div class="head-row">${action('library',icon('back'),'icon-btn','aria-label="返回离线缓存"')}<h2>本地播放</h2>${action('player-more',icon('more'),'icon-btn','aria-label="播放菜单"')}</div></header><div class="scroll"><div class="player-picture"><img src="assets/${m.cover}.svg" alt="${title}的播放画面示意"><div class="player-top"><span>${icon('shield')} 离线 · ${s.quality}</span>${action('fullscreen',icon('expand'),'text-btn','aria-label="全屏预览"')}</div>${s.danmaku ? '<div class="danmaku">这个风景值得慢慢看</div>' : ''}${action('play',icon(s.playing ? 'pause' : 'play'),'play-button',`aria-label="${s.playing ? '暂停播放' : '播放'}"`)}${s.language !== '关闭' ? `<div class="subtitle"><span>${subtitle}</span></div>` : ''}</div><div class="player-details"><h2>${title}</h2><div class="player-author">${icon('shield')} ${m.author} · 视频、弹幕、字幕已就绪</div><div class="scrubber"><label class="sr-only" for="seek-${id}">播放进度</label><input id="seek-${id}" data-action="seek" type="range" min="0" max="988" value="${s.position}" aria-label="播放进度"><div class="player-times"><span class="current-time">${time(s.position)}</span><span>16:28</span></div></div><div class="playback-tools">${action('speed',`${s.speed.toFixed(1)}×`)}${action('language',`${icon('captions')} ${s.language}`)}${action('danmaku',`${icon('chat')} 弹幕`,s.danmaku ? 'playing-mark' : '',`aria-pressed="${s.danmaku}"`)}</div><div class="section-title"><h3>已缓存选集</h3><span>${s.video === 0 ? '3 集' : '1 个视频'}</span></div><div class="episodes">${(s.video === 0 ? [0,1,3] : [s.episode]).map(i=>action('play-episode',`<span class="episode-number">${i === s.episode ? icon('bars') : String(i+1).padStart(2,'0')}</span><div class="episode-copy"><h3>${s.video === 0 ? episodes[i].title : m.title}</h3><p>${s.video === 0 ? episodes[i].duration : m.duration} · 1080P</p></div>${i === s.episode ? '<span class="tiny-tag">当前</span>' : ''}`,`episode ${i === s.episode ? 'selected' : ''}`,`data-index="${i}"`)).join('')}</div><p class="offline-footnote">每集播完停止，由你选择下一集。<br>离线进度单独保存。</p></div></div>`;
  }
  function modal(s) {
    if (!s.modal) return '';
    let content = '';
    if (s.modal.type === 'delete') {
      const marked = media.filter(m=>s.marked.has(m.id));
      const total = marked.reduce((n,m)=>n+m.count,0), mb = marked.reduce((n,m)=>n+m.size,0);
      content = `<h3>删除 ${total} 个已缓存视频？</h3><p>将释放 ${mb > 1000 ? `${(mb/1000).toFixed(2)} GB` : `${mb} MB`} 空间。包含所选合集中的全部已缓存分集。</p>${action('confirm-delete','删除缓存','primary-btn delete-btn')}`;
    } else if (s.modal.type === 'cellular') {
      content = `<h3>允许此任务使用蜂窝网络？</h3><p>仅放行本次选择的任务，其他任务继续等待 Wi-Fi。</p>${action('confirm-cellular','允许此任务','primary-btn')}`;
    } else if (s.modal.type === 'language') {
      content = `<h3>字幕语言</h3>${['中文','English','关闭'].map(value=>action('set-language',`${value}${s.language === value ? icon('check') : ''}`,'language-option',`data-value="${value}"`)).join('')}`;
    } else if (s.modal.type === 'group') {
      content = `<h3>把周末交给山野</h3><p>3 集已完整缓存 · 1080P · 1.26 GB</p><div class="episodes">${[0,1,3].map(i=>action('group-play',`<span class="episode-number">${String(i+1).padStart(2,'0')}</span><div class="episode-copy"><h3>${episodes[i].title}</h3><p>${episodes[i].duration} · 可离线观看</p></div>${icon('play')}`,'episode',`data-index="${i}"`)).join('')}</div>${action('delete-group','删除整组','primary-btn delete-btn')}`;
    } else if (s.modal.type === 'task-quality') {
      content = `<h3>更换缓存画质</h3><p>新的画质完整下载后，才会替换原有缓存。</p>${['720P','1080P','4K'].map(q=>action('set-task-quality',q,'language-option',`data-value="${q}"`)).join('')}`;
    } else if (s.modal.type === 'fullscreen') {
      content = `<h3>全屏播放</h3><img src="assets/${media[s.video].cover}.svg" alt="全屏画面示意" style="border-radius:12px;aspect-ratio:16/10"><p style="margin-top:4cqw">本地播放 · ${s.quality} · ${s.language}字幕</p>${action('play',s.playing ? '暂停播放' : '播放','primary-btn')}`;
    } else {
      content = `<h3>播放选项</h3>${action('language',`${icon('captions')} 字幕：${s.language}`,'language-option')}${action('speed',`播放速度：${s.speed.toFixed(1)}×`,'language-option')}${action('finish','跳到片尾','language-option')}`;
    }
    return `<div class="modal-scrim"><div class="dialog" role="dialog" aria-modal="true" aria-label="${s.modal.type === 'delete' ? '删除确认' : '选项'}">${content}${action('close-modal','取消','primary-btn cancel-modal')}</div></div>`;
  }
  function renderPhone(id) {
    const s = state[id], el = document.querySelector(`[data-concept="${id}"] .screen`);
    const scroll = el.querySelector('.scroll')?.scrollTop || 0;
    el.className = `screen ${s.stage}-page`;
    el.innerHTML = (s.stage === 'select' ? selection(id,s) : s.stage === 'downloads' ? downloads(id,s) : s.stage === 'player' ? player(id,s) : library(id,s)) + modal(s) + '<div class="phone-toast" role="status" aria-live="polite"></div>';
    if (el.querySelector('.scroll')) el.querySelector('.scroll').scrollTop = s.restoreScroll ? scroll : 0;
    s.restoreScroll = false;
    if (s.modal) el.querySelector('.dialog button')?.focus({preventScroll:true});
  }
  function toast(id,text) { const el = document.querySelector(`[data-concept="${id}"] .phone-toast`); if (!el) return; el.textContent = text; setTimeout(()=>{ if(el.isConnected) el.textContent=''; },2500); }
  function globalToast(text) { const el=document.getElementById('global-toast'); el.textContent=text; setTimeout(()=>el.textContent='',2800); }
  function navigate(s,stage) { s.stage=stage; s.modal=null; s.editing=false; s.marked.clear(); }
  function screenAction(id,button) {
    const s=state[id], name=button.dataset.action, index=Number(button.dataset.index), taskID=Number(button.dataset.id), value=button.dataset.value;
    const task=s.tasks.find(t=>t.id===taskID);
    s.restoreScroll=true;
    let message='';
    if (['library','downloads'].includes(name)) navigate(s,name);
    else if (name === 'exit') { message='返回「我的」；本页展示缓存功能原型'; }
    else if (name === 'edit') { if (s.stage==='downloads') { message='每个任务可独立暂停、继续或取消'; } else { s.editing=!s.editing; s.marked.clear(); } }
    else if (name === 'open') {
      if (s.editing) { s.marked.has(taskID) ? s.marked.delete(taskID) : s.marked.add(taskID); }
      else if (taskID===0) s.modal={type:'group'};
      else { s.video=taskID; s.position=504; s.playing=false; navigate(s,'player'); }
    } else if (name === 'episode') { s.selected.has(index) ? s.selected.delete(index) : s.selected.add(index); }
    else if (name === 'quality') s.quality=value;
    else if (name === 'scope') { s.scope=value; s.selected=new Set([1]); }
    else if (name === 'all') s.selected=s.selected.size===episodes.length ? new Set() : new Set(episodes.map((_,i)=>i));
    else if (name === 'start') {
      const count=s.selected.size;
      s.tasks=[...s.selected].map((i,n)=>({id:100+n,title:`${s.scope === 'parts' ? `P${i+1} · ` : ''}${episodes[i].title}`,cover:'mountain',quality:s.quality,progress:0,status:'wifi',size:Math.round(episodes[i].size*(s.quality==='4K'?2.7:s.quality==='720P'?.62:1))}));
      navigate(s,'downloads'); message=`已添加 ${count} 项，等待 Wi-Fi`;
    } else if (name === 'delete') s.modal={type:'delete'};
    else if (name === 'confirm-delete') { for(const mark of s.marked) s.deleted.add(mark); s.marked.clear(); s.modal=null; s.editing=false; message='所选缓存已删除（演示）'; }
    else if (name === 'delete-group') { s.marked=new Set([0]); s.modal={type:'delete'}; }
    else if (name === 'task-toggle' && task) {
      if(task.status==='wifi') s.modal={type:'cellular',id:taskID};
      else { task.status=task.status==='active'?'paused':'active'; message=task.status==='paused'?'已暂停，需要手动继续':'继续下载'; }
    } else if (name === 'cellular') s.modal={type:'cellular',id:taskID};
    else if (name === 'confirm-cellular') { const t=s.tasks.find(t=>t.id===s.modal.id); if(t){t.status='active';t.progress=Math.max(t.progress,14);} s.modal=null; message='仅此任务已允许使用蜂窝网络'; }
    else if (name === 'retry' && task) { task.status='active'; message='保留已完成资源，正在补全字幕'; }
    else if (name === 'cancel-task') { s.tasks=s.tasks.filter(t=>t.id!==taskID); message='下载任务已取消'; }
    else if (name === 'task-quality') s.modal={type:'task-quality',id:taskID};
    else if (name === 'set-task-quality') { const t=s.tasks.find(t=>t.id===s.modal.id); if(t){t.quality=value;t.progress=0;t.status='wifi';} s.modal=null; message='新画质已加入下载，原有缓存继续保留'; }
    else if (name === 'close-modal') s.modal=null;
    else if (name === 'group-play') { s.video=0;s.episode=index;s.position=504;s.playing=false;navigate(s,'player'); }
    else if (name === 'play') { if(s.position===988) s.position=0; s.playing=!s.playing; message=s.playing?'播放状态预览 · 示例画面':'已暂停'; }
    else if (name === 'play-episode') { s.episode=index;s.position=0;s.playing=false; }
    else if (name === 'language' || name === 'fullscreen') s.modal={type:name};
    else if (name === 'player-more') s.modal={type:'player-more'};
    else if (name === 'set-language') { s.language=value;s.modal=null; }
    else if (name === 'speed') { s.speed=({1:1.25,1.25:1.5,1.5:2,2:1})[s.speed]; }
    else if (name === 'danmaku') s.danmaku=!s.danmaku;
    else if (name === 'finish') { s.position=988;s.playing=false;s.modal=null;message='本集已播完，请手动选择下一集'; }
    else if (name === 'sort') s.reverse=!s.reverse;
    renderPhone(id);
    if(message) toast(id,message);
  }
  area.innerHTML=concepts.map(c=>`<article class="concept" data-concept="${c.id}"><header class="concept-title"><span class="concept-letter">${c.id.toUpperCase()}</span><h2>${c.name}</h2><button class="favorite" data-favorite="${c.id}" aria-label="喜欢${c.name}" aria-pressed="false">${icon('heart')}</button></header><div class="phone" aria-label="${c.name}手机界面"><div class="device-status"><span>9:41</span><span class="status-icons">${icon('signal')}${icon('wifi')}${icon('battery')}</span></div><div class="screen"></div><div class="device-bottom"></div><div class="home-indicator"></div></div><div class="concept-caption"><div class="kicker">${c.kicker}</div><p>${c.caption}</p><button class="detail-link" data-focus="${c.id}">单独查看 ${icon('arrow')}</button></div></article>`).join('');
  for (const c of concepts) renderPhone(c.id);
  document.querySelector('.focus-picks').innerHTML=concepts.map(c=>`<button data-focus="${c.id}" aria-label="查看${c.name}">${c.id.toUpperCase()}</button>`).join('');
  function setView(next,id=focus) {
    view=next;focus=id;area.classList.toggle('focus',next==='focus');
    document.querySelectorAll('[data-view]').forEach(b=>b.setAttribute('aria-pressed',b.dataset.view===next));
    document.querySelectorAll('.concept').forEach(el=>el.hidden=next==='focus'&&el.dataset.concept!==focus);
    document.querySelector('.focus-picks').hidden=next!=='focus';
    document.querySelectorAll('.focus-picks button').forEach(b=>b.classList.toggle('active',b.dataset.focus===focus));
    history.replaceState(null,'',`${location.pathname}${next==='focus'?`?design=${focus}`:''}#${currentStage}`);
  }
  function updateFavorites() {
    document.querySelectorAll('[data-favorite]').forEach(b=>b.setAttribute('aria-pressed',favorites.has(b.dataset.favorite)));
    document.querySelectorAll('.concept').forEach(el=>el.classList.toggle('favorite-concept',favorites.has(el.dataset.concept)));
    document.getElementById('favorite-summary').textContent=favorites.size ? `倾向：${concepts.filter(c=>favorites.has(c.id)).map(c=>`${c.id.toUpperCase()} ${c.name}`).join(' / ')}` : '尚未标记偏好';
  }
  function saveReview() { try { localStorage.setItem('neobili-offline-design-review',JSON.stringify({favorites:[...favorites],notes:notes.value})); } catch {} }
  document.addEventListener('click',event=>{
    const button=event.target.closest('button');if(!button || button.disabled)return;
    if(button.dataset.action){ const concept=button.closest('[data-concept]');if(concept)screenAction(concept.dataset.concept,button); }
    else if(button.dataset.stage){ currentStage=button.dataset.stage;document.querySelectorAll('[data-stage]').forEach(b=>b.setAttribute('aria-selected',b.dataset.stage===currentStage));for(const c of concepts){navigate(state[c.id],currentStage);renderPhone(c.id);}setView(view); }
    else if(button.dataset.view)setView(button.dataset.view);
    else if(button.dataset.focus){setView('focus',button.dataset.focus);document.querySelector('.review-toolbar').scrollIntoView({behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'auto':'smooth',block:'start'});}
    else if(button.dataset.favorite){ const id=button.dataset.favorite;favorites.has(id)?favorites.delete(id):favorites.add(id);updateFavorites();saveReview(); }
    else if(button.id==='reset-demo'){for(const c of concepts){state[c.id]=freshState();state[c.id].stage=currentStage;renderPhone(c.id);}globalToast('演示状态已重置，评审意见已保留');}
    else if(button.id==='copy-review')copyReview();
  });
  document.addEventListener('input',event=>{
    if(event.target===notes){saveReview();return;}
    if(event.target.dataset.action==='seek'){
      const id=event.target.closest('[data-concept]').dataset.concept,s=state[id];s.position=Number(event.target.value);
      event.target.closest('.scrubber').querySelector('.current-time').textContent=time(s.position);
      if(s.position===988){s.playing=false;renderPhone(id);toast(id,'本集已播完，请手动选择下一集');}
    }
  });
  document.addEventListener('keydown',event=>{
    const concept=event.target.closest('[data-concept]');if(!concept)return;
    const s=state[concept.dataset.concept];if(!s.modal)return;
    if(event.key==='Escape'){s.modal=null;renderPhone(concept.dataset.concept);concept.querySelector('.screen button')?.focus();}
    if(event.key==='Tab'){
      const buttons=[...concept.querySelectorAll('.dialog button:not(:disabled)')],first=buttons[0],last=buttons.at(-1);
      if(event.shiftKey&&event.target===first){event.preventDefault();last?.focus();}
      else if(!event.shiftKey&&event.target===last){event.preventDefault();first?.focus();}
    }
  });
  async function copyReview(){
    const text=`NeoBili 缓存界面评审\n${document.getElementById('favorite-summary').textContent}\n${notes.value || '暂无补充意见'}`;
    try{await navigator.clipboard.writeText(text);globalToast('评审意见已复制，可以发到对话中');}
    catch{notes.value=text;notes.focus();notes.select();globalToast('请复制选中的评审意见');}
  }
  updateFavorites();
  const initial=new URLSearchParams(location.search).get('design');
  const initialStage=location.hash.slice(1);
  if(['library','select','downloads','player'].includes(initialStage)) document.querySelector(`[data-stage="${initialStage}"]`).click();
  if(state[initial])setView('focus',initial);
})();
