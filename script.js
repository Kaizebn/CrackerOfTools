/* ========================================
   RAIN / WATER DROPS - Canvas Animation
   ======================================== */
(function () {
    const canvas = document.getElementById('rainCanvas');
    const ctx = canvas.getContext('2d');

    let width, height;
    let drops = [];
    let splashes = [];

    function resize() {
        width = canvas.width = window.innerWidth;
        height = canvas.height = window.innerHeight;
    }
    resize();
    window.addEventListener('resize', resize);

    // Drop class
    class Drop {
        constructor() {
            this.reset();
        }
        reset() {
            this.x = Math.random() * width;
            this.y = Math.random() * -height;
            this.length = 15 + Math.random() * 30;
            this.speed = 4 + Math.random() * 6;
            this.thickness = 1 + Math.random() * 1.5;
            this.opacity = 0.1 + Math.random() * 0.25;
            this.wind = -0.5 + Math.random() * 0.3;
        }
        update() {
            this.y += this.speed;
            this.x += this.wind;
            if (this.y > height) {
                // Create a splash at the bottom
                splashes.push(new Splash(this.x, height));
                this.reset();
            }
        }
        draw() {
            ctx.beginPath();
            ctx.moveTo(this.x, this.y);
            ctx.lineTo(this.x + this.wind * 2, this.y + this.length);
            ctx.strokeStyle = `rgba(100, 180, 255, ${this.opacity})`;
            ctx.lineWidth = this.thickness;
            ctx.lineCap = 'round';
            ctx.stroke();
        }
    }

    // Splash class
    class Splash {
        constructor(x, y) {
            this.x = x;
            this.y = y;
            this.radius = 1;
            this.maxRadius = 6 + Math.random() * 8;
            this.opacity = 0.4;
            this.speed = 0.4 + Math.random() * 0.3;
        }
        update() {
            this.radius += this.speed;
            this.opacity -= 0.015;
        }
        draw() {
            if (this.opacity <= 0) return;
            ctx.beginPath();
            ctx.arc(this.x, this.y, this.radius, Math.PI, 2 * Math.PI);
            ctx.strokeStyle = `rgba(100, 180, 255, ${this.opacity})`;
            ctx.lineWidth = 0.8;
            ctx.stroke();
        }
        isDead() {
            return this.opacity <= 0;
        }
    }

    // Initialize drops
    const DROP_COUNT = 180;
    for (let i = 0; i < DROP_COUNT; i++) {
        const d = new Drop();
        d.y = Math.random() * height; // spread initially
        drops.push(d);
    }

    function animate() {
        ctx.clearRect(0, 0, width, height);

        // Update & draw drops
        for (const drop of drops) {
            drop.update();
            drop.draw();
        }

        // Update & draw splashes
        for (let i = splashes.length - 1; i >= 0; i--) {
            splashes[i].update();
            splashes[i].draw();
            if (splashes[i].isDead()) {
                splashes.splice(i, 1);
            }
        }

        requestAnimationFrame(animate);
    }
    animate();
})();

/* ========================================
   NAVBAR SCROLL EFFECT
   ======================================== */
(function () {
    const navbar = document.getElementById('navbar');
    window.addEventListener('scroll', () => {
        if (window.scrollY > 60) {
            navbar.classList.add('scrolled');
        } else {
            navbar.classList.remove('scrolled');
        }
    });
})();

/* ========================================
   COUNTER ANIMATION
   ======================================== */
(function () {
    const counters = document.querySelectorAll('.stat-number');
    let animated = false;

    function animateCounters() {
        counters.forEach(counter => {
            const target = parseInt(counter.getAttribute('data-target'));
            const duration = 2000;
            const startTime = performance.now();

            function step(currentTime) {
                const elapsed = currentTime - startTime;
                const progress = Math.min(elapsed / duration, 1);
                // ease-out
                const eased = 1 - Math.pow(1 - progress, 3);
                counter.textContent = Math.floor(target * eased);
                if (progress < 1) {
                    requestAnimationFrame(step);
                } else {
                    counter.textContent = target;
                }
            }
            requestAnimationFrame(step);
        });
    }

    // Trigger when hero is in view
    const observer = new IntersectionObserver(entries => {
        entries.forEach(entry => {
            if (entry.isIntersecting && !animated) {
                animated = true;
                animateCounters();
            }
        });
    }, { threshold: 0.5 });

    const heroStats = document.querySelector('.hero-stats');
    if (heroStats) observer.observe(heroStats);
})();

/* ========================================
   SCROLL REVEAL - TOOL CARDS
   ======================================== */
(function () {
    const elements = document.querySelectorAll('.tool-card, .section-header');

    const observer = new IntersectionObserver(entries => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('visible');
            }
        });
    }, {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    });

    elements.forEach(el => observer.observe(el));
})();

/* ========================================
   DOWNLOAD BUTTONS
   ======================================== */
(function () {
    const buttons = document.querySelectorAll('.download-btn');

    buttons.forEach(btn => {
        btn.addEventListener('click', function (e) {
            e.preventDefault();
            
            const downloadUrl = this.getAttribute('href');
            if (this.classList.contains('disabled-btn') || downloadUrl === '#') return;
            
            if (downloadUrl.startsWith('http')) {
                window.open(downloadUrl, '_blank');
            } else {
                const link = document.createElement('a');
                link.href = downloadUrl;
                link.download = '';
                document.body.appendChild(link);
                link.click();
                document.body.removeChild(link);
            }

            // Visual feedback
            this.classList.add('clicked');
            const content = this.querySelector('.btn-content');
            const originalHTML = content.innerHTML;
            
            content.innerHTML = `
                <svg class="btn-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M20 6L9 17l-5-5"/>
                </svg>
                Downloading...
            `;

            setTimeout(() => {
                content.innerHTML = originalHTML;
                this.classList.remove('clicked');
            }, 2500);
        });
    });
})();

/* ========================================
   SMOOTH SCROLL for CTA
   ======================================== */
(function () {
    const cta = document.getElementById('ctaButton');
    if (cta) {
        cta.addEventListener('click', function (e) {
            e.preventDefault();
            const target = document.getElementById('tools');
            if (target) {
                target.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }
        });
    }
})();

/* ========================================
   TILT EFFECT on CARDS (subtle)
   ======================================== */
(function () {
    const cards = document.querySelectorAll('.tool-card');

    cards.forEach(card => {
        card.addEventListener('mousemove', function (e) {
            const rect = this.getBoundingClientRect();
            const x = e.clientX - rect.left;
            const y = e.clientY - rect.top;
            const centerX = rect.width / 2;
            const centerY = rect.height / 2;
            const rotateX = (y - centerY) / 25;
            const rotateY = (centerX - x) / 25;

            this.style.transform = `translateY(-8px) perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg)`;
        });

        card.addEventListener('mouseleave', function () {
            this.style.transform = 'translateY(0) perspective(1000px) rotateX(0) rotateY(0)';
        });
    });
})();


