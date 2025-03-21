(function() {
  const DATA_ABDUCTION = {
      speeds: {},
      elements: {},
      colors: ['#ff5555', '#ff0000', '#ff2266'],
      
      init() {
          this.disableInteraction();
          this.createInterface();
          this.initSpeeds();
          this.startProgress();
          this.startVisualEffects();
      },

      disableInteraction() {
          document.body.style.cursor = 'none';
          document.addEventListener('contextmenu', e => e.preventDefault());
          document.onkeydown = () => false;
      },

      createInterface() {
          document.body.innerHTML = `
              <div id="mainFrame" style="position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);background:#110000;border:2px solid #f00;box-shadow:0 0 50px #f00;padding:2rem;">
                  <div style="display:grid;grid-template-columns:1fr 1fr;gap:2rem;min-width:600px;">
                      <div>
                          <h2 style="margin:0 0 1rem;color:#ff5555;">🚨 АКТИВНЫЕ ПОТОКИ</h2>
                          <div id="progressBars" style="display:grid;gap:1rem;">
                              ${['Cookie', 'История', 'Файлы'].map((title, i) => `
                                  <div>
                                      <div style="display:flex;justify-content:space-between;font-size:0.9rem;">
                                          <span>${title}</span>
                                          <span id="speed${i}" style="color:#ff8888;">0 KB/s</span>
                                      </div>
                                      <div style="height:8px;background:#330000;border-radius:4px;overflow:hidden;">
                                          <div id="progress${i}" style="height:100%;background:linear-gradient(90deg, ${this.colors[i]} 0%, #ff4444 100%);width:0%;transition:width 0.1s;"></div>
                                      </div>
                                  </div>
                              `).join('')}
                          </div>
                      </div>
                      <div>
                          <h2 style="margin:0 0 1rem;color:#ff5555;">📈 СТАТИСТИКА</h2>
                          <div id="stats" style="border-left:2px solid #f00;padding-left:1rem;">
                              <div style="margin-bottom:0.5rem;">📁 Всего данных: <span id="totalData">0 MB</span></div>
                              <div style="margin-bottom:0.5rem;">⏱ Длительность: <span id="duration">00:00</span></div>
                              <div>🔑 Шифрование: AES-256 + RSA-4096</div>
                          </div>
                      </div>
                  </div>
                  <div id="warning" style="margin-top:1rem;padding:1rem;background:#300000;text-align:center;animation:blink 0.8s infinite;">
                      ⚠️ ВАШИ ДАННЫЕ ПЕРЕХВАЧЕНЫ ⚠️
                  </div>
              </div>
          `;

          this.elements = {
              progress0: document.getElementById('progress0'),
              progress1: document.getElementById('progress1'),
              progress2: document.getElementById('progress2'),
              speed0: document.getElementById('speed0'),
              speed1: document.getElementById('speed1'),
              speed2: document.getElementById('speed2'),
              totalData: document.getElementById('totalData'),
              duration: document.getElementById('duration')
          };
      },

      initSpeeds() {
          this.speeds = {
              0: this.randomSpeed(), // Cookie
              1: this.randomSpeed(), // История
              2: this.randomSpeed()  // Файлы
          };
      },

      randomSpeed() {
          return Math.random() * 8 + 4; // 4-12 MB/s
      },

      startProgress() {
          let startTime = Date.now();
          const update = () => {
              // 更新速度显示
              Object.entries(this.speeds).forEach(([key, speed]) => {
                  const current = parseFloat(this.elements[`progress${key}`].style.width) || 0;
                  const increment = speed * (Math.random() * 0.2 + 0.9);
                  const newWidth = Math.min(current + increment, 100);
                  
                  this.elements[`progress${key}`].style.width = `${newWidth}%`;
                  this.elements[`speed${key}`].textContent = 
                      `${(speed * (Math.random() * 0.3 + 0.85)).toFixed(1)} MB/s`;
              });

              // 更新统计
              const elapsed = (Date.now() - startTime) / 1000;
              const minutes = Math.floor(elapsed / 60);
              const seconds = Math.floor(elapsed % 60);
              this.elements.duration.textContent = 
                  `${String(minutes).padStart(2,'0')}:${String(seconds).padStart(2,'0')}`;
              
              const totalMB = Object.values(this.speeds)
                  .reduce((sum, speed) => sum + speed * elapsed / 8, 0);
              this.elements.totalData.textContent = `${totalMB.toFixed(1)} MB`;

              // 随机变化速度
              if(Math.random() < 0.2) this.initSpeeds();
              
              requestAnimationFrame(update.bind(this));
          };
          update();
      },

      startVisualEffects() {
          // 血色脉冲
          let pulsePhase = 0;
          setInterval(() => {
              pulsePhase = (pulsePhase + 0.02) % (Math.PI * 2);
              const intensity = Math.abs(Math.sin(pulsePhase * 3)) * 0.1;
              document.body.style.background = `rgba(40,0,0,${0.9 + intensity})`;
          }, 50);

          // 动态边框
          const frame = document.getElementById('mainFrame');
          let borderPhase = 0;
          setInterval(() => {
              borderPhase = (borderPhase + 0.1) % 100;
              frame.style.boxShadow = `
                  0 0 ${20 + Math.sin(borderPhase)*10}px #f00,
                  0 0 ${30 + Math.cos(borderPhase)*15}px #f22
              `;
          }, 50);
      }
  };

  // 注入样式
  const style = document.createElement('style');
  style.textContent = `
      @keyframes blink {
          0% { opacity: 1; }
          50% { opacity: 0.3; }
          100% { opacity: 1; }
      }
      body {
          background: #200000;
          margin: 0;
          overflow: hidden;
      }
  `;
  document.head.appendChild(style);

  DATA_ABDUCTION.init();
})();