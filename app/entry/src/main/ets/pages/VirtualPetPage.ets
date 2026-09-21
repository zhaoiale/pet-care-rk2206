// VirtualPetPage.ets — 电子萌宠页面（Emoji + 粒子特效）
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { getPet, getCurrentPetId } from '../utils/PetDataManager';
import { getLatestRecord } from '../database/DatabaseService';
import { InteractionRecord, insertInteractionRecord, getInteractionRecordsByPet } from '../database/DatabaseService';
import { isCat } from '../model/Pet';
import { SensorRecord } from '../model/SensorRecord';
import { Pet } from '../model/Pet';
import { lastAiInterpretation } from '../services/MqttService';

type EmotionType = 'happy' | 'calm' | 'alert' | 'anxious';

interface Particle {
  x: number;
  y: number;
  speed: number;
  size?: number;
}

interface ChatMessage {
  role: string;
  content: string;
}

function getIntentLabel(intent: string): string {
  switch (intent) {
    case 'hungry': return '饿了讨食';
    case 'happy': return '开心撒娇';
    case 'warning': return '警戒';
    case 'lonely': return '孤独呼唤';
    case 'play': return '想玩耍';
    case 'calm': return '安抚回应';
    default: return intent;
  }
}

@Entry
@Component
export struct VirtualPetPage {
  @State currentPet: Pet | null = null;
  @State anxietyLevel: number = 50;
  @State displayAnxiety: number = 50;
  @State emotion: EmotionType = 'calm';
  @State emotionText: string = '平静中...';
  @State isCat: boolean = false;
  @State interactionRecords: InteractionRecord[] = [];
  @State speechResult: string = '';
  @State showSpeechDialog: boolean = false;
  @State petName: string = '宠物';
  @State breedName: string = '';
  @State petEmoji: string = '🐶';
  @State breathScale: number = 1.0;
  @State particleTick: number = 0;
  @State aiInterpretation: string = '';
  @State humanText: string = '';
  @State petReply: string = '';
  @State isTranslating: boolean = false;
  @State chatMessages: ChatMessage[] = [];
  @State chatInput: string = '';

  private comfortTimer: number | null = null;
  private refreshTimer: number | null = null;
  private animFrame: number = -1;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private sweatDrops: Particle[] = [];
  private hearts: Particle[] = [];
  private tears: Particle[] = [];

  async aboutToAppear() {
    await this.loadPet();
    await this.loadLatestData();
    await this.loadInteractionRecords();
    this.startRefreshTimer();
    this.startBreathingAnimation();
  }

  aboutToDisappear() {
    if (this.comfortTimer !== null) clearTimeout(this.comfortTimer);
    if (this.refreshTimer !== null) clearInterval(this.refreshTimer);
    if (this.animFrame !== -1) clearTimeout(this.animFrame);
  }

  startBreathingAnimation() {
    const animate = () => {
      this.breathScale = 1.0 + Math.sin(Date.now() / 600) * 0.04;
      this.particleTick++;
      this.updateParticles();
      this.drawParticles();
      this.animFrame = setTimeout(animate, 50);
    };
    animate();
  }

  async loadPet() {
    const petId = getCurrentPetId();
    if (petId > 0) {
      const pet = await getPet(petId);
      if (pet !== null) {
        this.currentPet = pet;
        this.petName = pet.name || '宠物';
        this.breedName = pet.breed || '';
        this.isCat = isCat(pet.breed);
        this.updateEmoji();
      }
    }
  }

  async loadLatestData() {
    const record = await getLatestRecord();
    if (record !== null) {
      this.anxietyLevel = record.anxietyLevel;
      if (this.comfortTimer === null) {
        this.displayAnxiety = record.anxietyLevel;
      }
      this.updateEmotion(this.displayAnxiety);
    }
  }

  async loadInteractionRecords() {
    const petId = getCurrentPetId();
    if (petId > 0) {
      this.interactionRecords = await getInteractionRecordsByPet(petId, 20);
    }
  }

  startRefreshTimer() {
    const timer = setInterval(async () => {
      await this.loadLatestData();
      await this.loadInteractionRecords();
      this.aiInterpretation = lastAiInterpretation || '';
    }, 5000);
    this.refreshTimer = timer as Object as number;
  }

  updateEmoji() {
    if (this.isCat) {
      switch (this.emotion) {
        case 'happy': this.petEmoji = '😸'; break;
        case 'anxious': this.petEmoji = '😾'; break;
        default: this.petEmoji = '🐱'; break;
      }
    } else {
      switch (this.emotion) {
        case 'happy': this.petEmoji = '🐶'; break;
        case 'alert': this.petEmoji = '🐕'; break;
        case 'anxious': this.petEmoji = '🐶'; break;
        default: this.petEmoji = '🐶'; break;
      }
    }
  }

  updateEmotion(level: number) {
    if (level <= 15) {
      this.emotion = 'happy';
      this.emotionText = '高兴玩耍中~';
    } else if (level <= 35) {
      this.emotion = 'calm';
      this.emotionText = '平静中...';
    } else if (level <= 60) {
      this.emotion = 'alert';
      this.emotionText = '警觉观察中...';
    } else {
      this.emotion = 'anxious';
      this.emotionText = '焦虑不安...';
    }
    this.updateEmoji();
  }

  updateParticles() {
    this.sweatDrops = this.sweatDrops.filter((drop: Particle) => {
      drop.y += drop.speed;
      return drop.y < 300;
    });
    this.hearts = this.hearts.filter((heart: Particle) => {
      heart.y -= heart.speed;
      return heart.y > -30;
    });
    this.tears = this.tears.filter((tear: Particle) => {
      tear.y += tear.speed;
      return tear.y < 300;
    });

    if (this.emotion === 'anxious' && Math.random() > 0.92) {
      this.sweatDrops.push({ x: 80 + Math.random() * 140, y: 160, speed: 1.5 + Math.random() * 2 });
      this.tears.push({ x: 110 + Math.random() * 80, y: 140, speed: 2 + Math.random() * 2 });
    }
    if (this.emotion === 'happy' && Math.random() > 0.92) {
      this.hearts.push({ x: 100 + Math.random() * 100, y: 240, speed: 1.5 + Math.random() * 2, size: 8 + Math.random() * 12 });
    }
  }

  drawParticles() {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, 300, 300);

    // Sweat drops
    ctx.fillStyle = '#87CEEB';
    this.sweatDrops.forEach((drop: Particle) => {
      ctx.beginPath();
      ctx.ellipse(drop.x, drop.y, 5, 8, 0, 0, Math.PI * 2);
      ctx.fill();
    });

    // Hearts
    ctx.fillStyle = '#FF69B4';
    this.hearts.forEach((heart: Particle) => {
      const s = heart.size ?? 10;
      ctx.beginPath();
      ctx.moveTo(heart.x, heart.y);
      ctx.bezierCurveTo(heart.x - s / 2, heart.y - s / 2, heart.x - s, heart.y + s / 3, heart.x, heart.y + s);
      ctx.bezierCurveTo(heart.x + s, heart.y + s / 3, heart.x + s / 2, heart.y - s / 2, heart.x, heart.y);
      ctx.fill();
    });

    // Tears
    ctx.fillStyle = 'rgba(135, 206, 235, 0.85)';
    this.tears.forEach((tear: Particle) => {
      ctx.beginPath();
      ctx.ellipse(tear.x, tear.y, 4, 7, 0, 0, Math.PI * 2);
      ctx.fill();
    });
  }

  async handleComfort(type: string) {
    await this.saveInteraction(type, '手动安抚');

    let newLevel = this.displayAnxiety - 20;
    if (newLevel < 0) newLevel = 0;
    this.displayAnxiety = newLevel;
    this.updateEmotion(newLevel);

    for (let i = 0; i < 6; i++) {
      setTimeout(() => {
        this.hearts.push({ x: 100 + Math.random() * 100, y: 250, speed: 1.5 + Math.random() * 2, size: 8 + Math.random() * 12 });
      }, i * 120);
    }

    if (this.comfortTimer !== null) clearTimeout(this.comfortTimer);
    const timer = setTimeout(() => {
      this.displayAnxiety = this.anxietyLevel;
      this.updateEmotion(this.anxietyLevel);
      this.comfortTimer = null;
    }, 30000);
    this.comfortTimer = timer as Object as number;
  }

  async handleVoiceRecognition() {
    try {
      await promptAction.showDialog({
        title: '语音识别',
        message: '请说出您想对宠物说的话（如：乖、别怕、过来）',
        buttons: [{ text: '确定', color: '#2196F3' }]
      });

      const testResponses = ['乖', '别怕', '过来', '吃饭', '睡觉', '开心'];
      const randomResponse = testResponses[Math.floor(Math.random() * testResponses.length)];
      this.speechResult = randomResponse;
      this.showSpeechDialog = true;
      await this.saveInteraction('voice', randomResponse);

      if (['乖', '别怕', '爱你', '亲亲', '抱抱', '过来'].some((k: string) => randomResponse.includes(k))) {
        this.handleComfort('语音安抚');
      } else if (['吃', '饭', '饿'].some((k: string) => randomResponse.includes(k))) {
        await promptAction.showDialog({
          title: '宠物回应',
          message: `${this.petName}摇着尾巴跑过来了！`,
          buttons: [{ text: '确定', color: '#4CAF50' }]
        });
      } else if (['睡', '困'].some((k: string) => randomResponse.includes(k))) {
        this.displayAnxiety = Math.max(0, this.displayAnxiety - 10);
        this.updateEmotion(this.displayAnxiety);
      } else {
        this.emotionText = '歪着头好奇地看着你...';
      }
    } catch (err) {
      console.error('[VirtualPet] Voice recognition error:', JSON.stringify(err as Object));
      await promptAction.showDialog({
        title: '提示',
        message: '语音识别功能暂不可用',
        buttons: [{ text: '确定', color: '#2196F3' }]
      });
    }
  }

  async handleAIChat() {
    if (this.chatInput.trim().length === 0 || this.isTranslating) return;
    const userMsg = this.chatInput.trim();
    this.chatInput = '';
    this.isTranslating = true;

    const userChatMsg: ChatMessage = { role: 'user', content: userMsg };
    this.chatMessages = [...this.chatMessages, userChatMsg];

    // 模拟宠物思考延迟(300~800ms)
    await new Promise<void>((r: Function) => setTimeout(r, 300 + Math.random() * 500));

    const reply = this.mockPetReply(userMsg);
    const replyMsg: ChatMessage = { role: 'pet', content: reply };
    this.chatMessages = [...this.chatMessages, replyMsg];
    await this.saveInteraction('ai_chat', userMsg + ' → ' + reply.substring(0, 30));
    this.isTranslating = false;
  }

  mockPetReply(userMsg: string): string {
    const msg = userMsg;
    const s = this.isCat ? '喵' : '汪';
    const cat = this.isCat;

    // 饮食
    if (this.matchAny(msg, ['饿', '吃', '饭', '粮', '零食', '罐头', '喂', '肉', '干', '饱'])) {
      return this.pick([
        `${s}${s}~ 饿了饿了！快给我好吃的，不然我要翻碗了！🐾`,
        `${s}！${cat ? '今天想吃金枪鱼罐头，不要那种便宜的！' : '肉肉！给我肉肉！我的尾巴在发电报了！'}`,
        `${s}${s}${s}~ ${cat ? '开饭开饭开饭！慢了我就抓沙发！' : '终于等到你！碗都空了三个小时了！'}`,
        `${s}~ ${cat ? '闻到了闻到了，是罐头对吗？对吗？！' : '口水都要滴键盘上了，快倒粮！'}💦`,
        `${s}...${this.petName}的肚子在咕咕叫了，主人你听见了吗？`,
        `${s}${s}！${cat ? '我要那个带汤的！不要干的！' : '今天可以多吃一根磨牙棒吗？求求了~'}`,
      ]);
    }

    // 玩耍
    if (this.matchAny(msg, ['玩', '球', '跑', '玩具', '逗猫棒', '飞盘', '绳', '追', '跳', '抓', '咬'])) {
      return this.pick([
        `${s}！${cat ? '逗猫棒在哪？我要抓抓抓！这次一定抓住它！' : '去公园吗去公园吗？我尾巴都要摇断了！'}🦴`,
        `${s}${s}${s}！${cat ? '红色激光点！我看到你了！别跑！咚——撞墙了...' : '飞盘飞盘飞盘！我今天能接十个！'}`,
        `${s}~ ${cat ? '那个带铃铛的小老鼠呢？我藏起来了，嘿嘿~' : '快扔球！我保证这次会叼回来...大概吧...'}`,
        `${s}！${cat ? '来决斗！看我喵喵拳！左右左右！' : '跑起来跑起来！今天我能绕小区三圈！'}⚡`,
        `${s}${s}~ ${cat ? '纸箱子！主人你拆快递了对不对？那个箱子是我的！' : '嗷呜~好无聊，陪我玩拔河游戏吧~'}`,
      ]);
    }

    // 撒娇/夸奖
    if (this.matchAny(msg, ['乖', '好', '棒', '亲', '爱', '抱', '摸', '蹭', '喜欢', '可爱', '漂亮', '帅', '乖'])) {
      return this.pick([
        `${s}~ ${cat ? '呼噜呼噜...再摸一会儿嘛，不要停~' : '好开心！舔舔主人的手！再来一次！'}💕`,
        `${s}${s}~ ${cat ? '踩奶踩奶踩奶...主人的腿最舒服了！' : '翻肚皮！快揉快揉！这里这里！'}`,
        `${s}~ ${cat ? '被夸了，尾巴翘高高~' : '被夸了！疯狂摇尾巴！摇成直升机了！'}✨`,
        `${s}~ ${cat ? '今天心情好，赏你摸一下我的肉垫~' : '把头搁在你膝盖上...我好爱你哦。'}`,
      ]);
    }

    // 睡觉
    if (this.matchAny(msg, ['睡', '觉', '困', '累', '晚安', '休息', '躺', '梦'])) {
      return this.pick([
        `${s}...已经困得睁不开眼了，梦里会有小鱼干吗...💤`,
        `${s}...zzZ...${s}...${cat ? '别吵...我在抓梦里的蝴蝶...' : '在梦里追兔子...别叫醒我...'}💤`,
        `${s}~ ${cat ? '太阳晒着好暖和，这就是猫生巅峰了吧...' : '找个小角落蜷起来，晚安主人~'}`,
        `${s}...${cat ? '你的键盘好暖和，我要睡在上面...' : '你的拖鞋旁边是我的专属位置，别换地方哦~'}😴`,
      ]);
    }

    // 叫/回应
    if (this.matchAny(msg, ['叫', '吼', '汪', '喵', '说话', '喊', '声', '听'])) {
      return this.pick([
        `${s.repeat(3)}！${cat ? '喵呜~我在呢！听见了听见了！' : '汪汪汪！有情况吗？哦就是想我了~'}`,
        `${s}${s}！${cat ? '喵嗷——翻译：我爱你！' : '嗷呜——翻译：我超爱你！'}`,
        `${s}~ ${cat ? '喵？你叫我呀？' : '汪？找我啥事？有吃的还是有玩的？'}`,
        `${s.repeat(2)}~ ${cat ? '（蹭过来）我来了我来了~' : '（飞奔过来）到达！请下达指令！'}`,
      ]);
    }

    // 身份
    if (this.matchAny(msg, ['你', '谁', '名字', '什么', '哪里来', '几岁'])) {
      return this.pick([
        `${s}~ 我是${this.petName}呀，你忘啦？我是你最可爱的${cat ? '小猫咪' : '小狗狗'}！`,
        `${s}？${cat ? '我是这个家的主子，你是铲屎官，别忘了自己的身份！😼' : '我是你的小跟班呀，你去哪我就去哪！'}🐾`,
        `${s}${s}~ ${cat ? '我叫' + this.petName + '，喵星喵，兴趣爱好：睡觉、抓沙发、吃罐头。' : '我叫' + this.petName + '，汪星汪，特长：接飞盘、卖萌、翻垃圾桶。'}`,
      ]);
    }

    // 出门/散步
    if (this.matchAny(msg, ['出门', '散步', '出去', '遛', '走', '外面', '公园', '下楼', '玩去'])) {
      return this.pick([
        `${s.repeat(3)}！${cat ? '出去？不不不，外面有狗/陌生人/风/雨/太阳...我在家就好！' : '走走走！我闻到了自由的味道！电梯等我！'}`,
        `${s}${s}！${cat ? '你是要出门上班了吗...早点回来，我会在窗台上等你...' : '散步散步散步！这个词我能听懂！绳呢？快点！'}`,
        `${s}~ ${cat ? '带着我！我要坐肩膀上视察领地！' : '今天能多走一圈吗？我保证不在草地上打滚——骗你的我肯定会！'}🌳`,
        `${s}！${cat ? '快递柜那边有只橘猫，上次还凶我...今天我要凶回去！' : '门口那只泰迪今天再冲我叫我就吼回去，我练了一周了！'}`,
      ]);
    }

    // 回家/想
    if (this.matchAny(msg, ['回', '来', '想', '等', '久', '不在', '去哪', '陪'])) {
      return this.pick([
        `${s}${s}${s}！！${cat ? '你终于回来了！我数了，从你出门到现在我已经叫了73次了！' : '啊啊啊你回来了！我以为你再也不回来了！跳起来扑你！'}`,
        `${s}~ ${cat ? '想你了...（假装不在意但尾巴缠着你的腿）' : '想你想得我都没心情拆家了...骗你的，沙发坏了。'}`,
        `${s}...${cat ? '下次别出去那么久，我一个人在家数窗帘穗子很无聊的...' : '8小时32分钟，你走了这么久，我的狗生失去了意义...'}`,
        `${s}！${cat ? '带什么好吃的回来了？先检查包！' : '抱抱抱抱抱抱！先抱五分钟再说别的！'}`,
      ]);
    }

    // 情绪 - 不开心
    if (this.matchAny(msg, ['不开心', '难过', '伤心', '哭', '生气', '烦', '累死', '压力', '不好', '难'])) {
      return this.pick([
        `${s}...${cat ? '过来，我陪你。用头蹭蹭你的手，一切都会好的。' : '把头放在你膝盖上，用最温柔的眼神看着你...'}`,
        `${s}~ ${cat ? '别难过，我的肉垫给你捏，很解压的！' : '别不开心啦，我来耍个宝逗你笑！看——转圈圈！摔倒了！'}`,
        `${s}...${cat ? '躺下来，呼噜声可以治愈一切，试试看~' : '我把最喜欢的玩具叼过来了，给你玩，别难过了！'}🎁`,
        `${s}${s}~ ${cat ? '来，给你吸一口猫，据说可以缓解压力。科学认证的。' : '舔舔你的脸...咸的！主人你在哭吗？别哭别哭！'}`,
      ]);
    }

    // 情绪 - 开心
    if (this.matchAny(msg, ['开心', '高兴', '快乐', '哈哈', '笑', '耶', '好耶', '爽', '不错', '挺'])) {
      return this.pick([
        `${s}${s}${s}！${cat ? '你开心我也开心！来追我的尾巴！看到了吗看到了吗？' : '你开心！我也开心！大家一起来转圈！晕了晕了...'}`,
        `${s}~ ${cat ? '看见你笑，我的呼噜频率自动提升了50%！' : '摇尾巴！摇到地板都要秃了！'}`,
        `${s}！${cat ? '那今天可以多开一盒罐头庆祝一下吗？' : '开心就带我出去疯跑！走！'}🎉`,
      ]);
    }

    // 骂/批评
    if (this.matchAny(msg, ['坏', '讨厌', '打', '骂', '罚', '错', '不行', '不许', '别', '停', '滚', '傻', '笨', '蠢'])) {
      return this.pick([
        `${s}...${cat ? '（耳朵压平）我错了...不对，我没错！但你先别生气...' : '（耳朵耷拉，尾巴夹紧）我知道错了...虽然不知道错哪了...'}`,
        `${s}？${cat ? '你凶我？好，我去鞋里睡觉了，别找我！' : '呜...我不是故意的，是沙发先动手的...'}`,
        `${s}...${cat ? '哼！（转身用屁股对着你，但尾巴还在偷偷观察你）' : '趴下，用最委屈的眼神看着你。这招每次都管用。'}`,
        `${s}${s}...${cat ? '好吧好吧，这次的卫生纸是我撕的。但你上次不也撕了我的猫抓板嘛...' : '我认罪。但我有苦衷——那个垃圾桶真的很香很香...'}`,
      ]);
    }

    // 洗澡/水
    if (this.matchAny(msg, ['洗澡', '水', '湿', '吹', '洗', '沐浴', '香'])) {
      return this.pick([
        `${s.repeat(3)}！${cat ? '不要水！不许靠近我！那个喷头我看见了！退退退！' : '洗澡？水？不要——你是不是不爱我了？！'}`,
        `${s}...${cat ? '我自己会舔干净，真的，不需要水...不需要...' : '上次洗澡是上辈子的事了，我感觉很干净——你闻闻，这叫狗味，是香的！'}🛁`,
        `${s}！${cat ? '你敢把我放进水里，我就把你手机推下桌子。说到做到。' : '好吧...但水温必须38度，洗发水要用那个椰子味的，吹风机开最小档！'}`,
      ]);
    }

    // 健康
    if (this.matchAny(msg, ['病', '痛', '难受', '医院', '医生', '药', '检查', '不舒服', '吐', '拉'])) {
      return this.pick([
        `${s}...${cat ? '有一点点不舒服，但不想去医院...那个白大褂太可怕了...' : '呜...我不喜欢那个温度计...不过如果你陪我的话，我勇敢一点...'}`,
        `${s}${s}...${cat ? '吐了个毛球而已，别大惊小怪啦~不过...你好像很担心？' : '今天肚子有点怪怪的，对不起在地毯上吐了一小滩...'}`,
        `${s}~ ${cat ? '我没事！睡一觉就好了！...不过你的手放在我额头上的时候好温柔。' : '有你在旁边我就不怕。那个穿白大褂的阿姨其实挺温柔的，还给零食。'}`,
      ]);
    }

    // 早上
    if (this.matchAny(msg, ['早', '早上', '早安', '起床', '醒', '天亮', '晨'])) {
      return this.pick([
        `${s}${s}！${cat ? '早上6点就该起来了！我的碗空了，太阳都晒屁股了！' : '早上了早上了！我已经醒了一个小时了，就等你这句话！'}`,
        `${s}~ ${cat ? '再睡五分钟...不，十分钟...算了你把我抱起来吧...' : '早安！今天先遛我还是先喂我？建议：同时进行！'}☀️`,
        `${s}！${cat ? '早~给你做了早安按摩——就是踩奶啦！免费服务！' : '早！我已经帮你把拖鞋叼来了，快夸我！'}`,
      ]);
    }

    // 拍照
    if (this.matchAny(msg, ['拍照', '照片', '合影', '自拍', '拍', '照片', '相机', '镜头'])) {
      return this.pick([
        `${s}？${cat ? '拍我？等下——这个角度！侧脸45度比较显瘦！好了拍吧！' : '拍照！等我摆个pose！（坐直，歪头，吐舌头）好了吗？'}`,
        `${s}~ ${cat ? '偷拍？我发现了！想拍就光明正大拍嘛，我又不会拒绝~' : '你在拿那个黑方块对着我吗？我过来闻闻这是什么东西——别动！'}`,
        `${s}${s}~ ${cat ? '来来来，和我一起拍！我要用爪子按快门！' : '能不能拍我在草丛里飞奔的？那才叫帅！'}📸`,
      ]);
    }

    // 指令/训练
    if (this.matchAny(msg, ['坐', '趴', '握手', '等', '来', '过来', '不行', '好狗', '好猫', '真'])) {
      return this.pick([
        `${s}！${cat ? '坐？我为什么要坐？你手里有零食吗？让我先看看再说...' : '（秒坐）坐好了！同时伸手要握手！我厉害吧！'}🐾`,
        `${s}~ ${cat ? '握手？行吧——（伸出爪子，但眼神写着"你欠我一顿罐头"）' : '握手握手握手！会！还会换手！还会击掌！还会——零食呢？'}`,
        `${s}${s}！${cat ? '过来？不，你过来。我们猫的生活准则第一条：不被召唤。' : '来了来了！（漂移过弯）我用了0.8秒就到位了！'}💨`,
      ]);
    }

    // 天气
    if (this.matchAny(msg, ['冷', '热', '太阳', '雨', '风', '雪', '阴', '晒', '凉'])) {
      return this.pick([
        `${s}~ ${cat ? '出太阳了——这个光斑是我的！谁也别跟我抢！' : '热死了热死了，舌头收不回去...这是什么鬼天气...'}☀️`,
        `${s}...${cat ? '外面下雨了，哪也不去。在被窝里团成一团，完美。' : '下雨了...不能出去跑步，狗生灰暗...除非你陪我在地下车库跑？'}🌧️`,
        `${s}！${cat ? '好冷，你的腿是我的专属暖气，别动。' : '下雪了！雪地里打滚是我与生俱来的使命，放我出去！'}❄️`,
      ]);
    }

    // 礼貌用语
    if (this.matchAny(msg, ['你好', '嗨', 'hello', 'hi', '喂', '在吗', '哈喽'])) {
      return this.pick([
        `${s}${s}~ ${cat ? '喵呀~在呢在呢！' : '汪呜~你好呀主人！今天有什么安排？'}`,
        `${s}！${cat ? '（从沙发上跳下来，伸个懒腰）你来啦~' : '（摇着尾巴跑过来）我在我在！一直在等你找我！'}`,
        `${s}~ ${cat ? '喵~（高冷地看了你一眼，但尾巴尖在偷偷摆动——它在开心）' : '嗨嗨嗨！（疯狂摇尾巴）终于有人理我了！'}`,
      ]);
    }

    // 告别
    if (this.matchAny(msg, ['拜', '再见', 'bye', '走了', '离开', '回见', '待会', '晚点', '明天'])) {
      return this.pick([
        `${s}...${cat ? '你要走了吗...我会在窗台上看着你走的...记得早点回来...' : '呜...要走了吗？我送你到门口...不对，你再坐五分钟吧！'}`,
        `${s}${s}...${cat ? '拜拜~我会想你的...然后在你回来前一秒假装在睡觉！' : '再见！我会乖乖看家的！——大概率会拆个抱枕，提前道歉...'}`,
        `${s}~ ${cat ? '等你哟~记得带罐头！' : '等你！带回点好吃的就更好了！'}👋`,
      ]);
    }

    // 随机（理解不了时）
    return this.pick([
      `${s}~ 虽然不太明白，但是很开心你跟我说话！`,
      `${s}${s}~ 主人你在说什么呀？反正我摇尾巴就对了！`,
      `${s}~ ${cat ? '蹭蹭你的腿~你说的都对！' : '用湿鼻子拱拱你的手~我永远支持你！'}`,
      `${s}！${cat ? '翻个肚皮给你看~看！我信任你！' : '转圈圈！转圈圈！转到头晕也要转给你看！'}`,
      `${s}~ 听不懂听不懂，但我永远爱你！💚`,
      `${s}${s}~ ${cat ? '歪头杀——你说什么？再说一遍？歪头看——好，还是没懂。' : '歪头——歪另一边——还是没懂，但我很认真在听了！'}`,
      `${s}~ ${cat ? '喵生最大的幸福就是和你在一起，虽然这句话我每天都说。' : '世界上有那么多狗，你选了我，我好幸运。汪~'}`,
      `${s}！${cat ? '其实我大部分时候都在装高冷，但我真的很喜欢跟你待在一起。' : '只要你在家，就算不陪我玩，我也觉得好安心。'}🏠`,
    ]);
  }

  matchAny(text: string, keywords: string[]): boolean {
    return keywords.some((k: string) => text.indexOf(k) >= 0);
  }

  pick(options: string[]): string {
    return options[Math.floor(Math.random() * options.length)];
  }

  async saveInteraction(type: string, content: string) {
    const petId = getCurrentPetId();
    if (petId > 0) {
      const record: InteractionRecord = {
        id: 0,
        petId: petId,
        interactionType: type,
        content: content,
        timestamp: Date.now()
      };
      await insertInteractionRecord(record);
      await this.loadInteractionRecords();
    }
  }

  formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const m = (date.getMonth() + 1).toString().padStart(2, '0');
    const d = date.getDate().toString().padStart(2, '0');
    const h = date.getHours().toString().padStart(2, '0');
    const min = date.getMinutes().toString().padStart(2, '0');
    return `${m}-${d} ${h}:${min}`;
  }

  getInteractionTypeLabel(type: string): string {
    switch (type) {
      case 'comfort': return '主人安抚';
      case 'voice': return '语音互动';
      case 'breathing': return '呼吸灯安抚';
      case 'whitenoise': return '白噪音安抚';
      case 'ai_chat': return 'AI对话';
      default: return type;
    }
  }

  build() {
    Column() {
      // Header
      Row() {
        Button('返回')
          .fontSize(16)
          .fontColor('#2196F3')
          .onClick(() => router.back())
        Blank()
        Text('电子萌宠')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text('').width(50)
      }
      .width('100%')
      .padding({ left: 15, right: 15, top: 15, bottom: 15 })

      Scroll() {
        Column() {
          // Pet info
          Text(`你的 ${this.breedName} ${this.petName}`)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333')
            .margin({ bottom: 10 })

          Text(this.emotionText)
            .fontSize(14)
            .fontColor('#666')
            .margin({ bottom: 15 })

          // Pet display area
          Stack() {
            // Background circle
            Column() {}
              .width(240)
              .height(240)
              .backgroundColor('#FFF8F0')
              .borderRadius(120)
              .border({ width: 2, color: '#F0E0D0' })

            // Pet emoji
            Text(this.petEmoji)
              .fontSize(110)
              .scale({ x: this.breathScale, y: this.breathScale })

            // Particle canvas overlay
            Canvas(this.ctx)
              .width(300)
              .height(300)
              .hitTestBehavior(HitTestMode.None)
              .onReady(() => { this.drawParticles(); })
          }
          .width(300)
          .height(300)
          .alignContent(Alignment.Center)
          .margin({ bottom: 15 })

          // Interaction buttons
          Button('主人语音')
            .width('85%')
            .height(55)
            .fontSize(18)
            .backgroundColor('#4CAF50')
            .borderRadius(28)
            .margin({ top: 10 })
            .onClick(() => this.handleVoiceRecognition())

          Row({ space: 15 }) {
            Button('呼吸灯')
              .width('30%')
              .height(45)
              .fontSize(14)
              .backgroundColor('#2196F3')
              .borderRadius(23)
              .onClick(() => this.handleComfort('breathing'))

            Button('白噪音')
              .width('30%')
              .height(45)
              .fontSize(14)
              .backgroundColor('#9C27B0')
              .borderRadius(23)
              .onClick(() => this.handleComfort('whitenoise'))

            Button('安抚')
              .width('30%')
              .height(45)
              .fontSize(14)
              .backgroundColor('#FF9800')
              .borderRadius(23)
              .onClick(() => this.handleComfort('comfort'))
          }
          .width('85%')
          .margin({ top: 15 })

          // AI 对话
          Column() {
            Text('和 ' + this.petName + ' 聊天')
              .fontSize(14)
              .fontColor('#666')
              .margin({ bottom: 8 })

            // 消息列表
            if (this.chatMessages.length === 0) {
              Text('对我说点什么吧~')
                .fontSize(13)
                .fontColor('#CCC')
                .margin({ top: 20, bottom: 20 })
            } else {
              List({ space: 8 }) {
                ForEach(this.chatMessages, (msg: ChatMessage, idx: number) => {
                  ListItem() {
                    Row() {
                      if (msg.role === 'pet') {
                        Row() {
                          Text(this.isCat ? '🐱' : '🐶')
                            .fontSize(18)
                            .margin({ right: 6 })
                          Text(msg.content)
                            .fontSize(13)
                            .fontColor('#333')
                            .backgroundColor('#F0E6FF')
                            .borderRadius(12)
                            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                            .constraintSize({ maxWidth: '65%' })
                        }
                        .alignItems(VerticalAlign.Top)
                        .width('100%')
                        .justifyContent(FlexAlign.Start)
                      } else {
                        Text(msg.content)
                          .fontSize(13)
                          .fontColor('#FFF')
                          .backgroundColor('#6C47FF')
                          .borderRadius(12)
                          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                          .constraintSize({ maxWidth: '75%' })
                      }
                    }
                    .width('100%')
                    .justifyContent(msg.role === 'pet' ? FlexAlign.Start : FlexAlign.End)
                  }
                }, (_msg: ChatMessage, idx: number) => idx.toString())
              }
              .width('100%')
              .height(200)
              .scrollBar(BarState.Off)
            }

            // 输入栏
            Row() {
              TextInput({ placeholder: '输入想说的话...', text: this.chatInput })
                .layoutWeight(1)
                .height(42)
                .fontSize(14)
                .backgroundColor('#FFF')
                .borderRadius(21)
                .padding({ left: 16, right: 16 })
                .onChange((value: string) => { this.chatInput = value; })
                .onSubmit(() => { this.handleAIChat(); })
              Button('发送')
                .width(60)
                .height(42)
                .fontSize(14)
                .backgroundColor('#6C47FF')
                .borderRadius(21)
                .margin({ left: 8 })
                .enabled(!this.isTranslating)
                .onClick(() => { this.handleAIChat(); })
            }
            .width('100%')
            .margin({ top: 8 })
          }
          .width('85%')
          .margin({ top: 12 })

          // AI 解读卡片
          if (this.aiInterpretation.length > 0) {
            Row() {
              Column() {
                Row() {
                  Text('AI 解读')
                    .fontSize(11).fontColor('#6C47FF')
                    .fontWeight(FontWeight.Medium)
                  Text(' DeepSeek')
                    .fontSize(9).fontColor('#6C47FF')
                    .opacity(0.6)
                    .margin({ left: 4 })
                }
                .margin({ bottom: 4 })
                Text(this.aiInterpretation)
                  .fontSize(13).fontColor('#333')
                  .lineHeight(20)
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%').padding(12)
              .backgroundColor('#F5F0FF').borderRadius(8)
            }
            .width('85%').margin({ top: 12 })
          }

          // Interaction records
          Column() {
            Text('互动记录')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333')
              .margin({ bottom: 10 })

            if (this.interactionRecords.length === 0) {
              Text('暂无互动记录')
                .fontSize(14)
                .fontColor('#999')
            } else {
              List({ space: 10 }) {
                ForEach(this.interactionRecords, (record: InteractionRecord) => {
                  ListItem() {
                    Row() {
                      Text(this.formatTime(record.timestamp))
                        .fontSize(12)
                        .fontColor('#999')
                        .width(100)
                      Text(this.getInteractionTypeLabel(record.interactionType))
                        .fontSize(14)
                        .fontColor('#333')
                      if (record.content && record.interactionType === 'voice') {
                        Text(`"${record.content}"`)
                          .fontSize(12)
                          .fontColor('#666')
                          .fontStyle(FontStyle.Italic)
                      }
                    }
                    .width('100%')
                    .padding({ left: 15, right: 15, top: 10, bottom: 10 })
                    .backgroundColor('#F5F5F5')
                    .borderRadius(10)
                  }
                }, (record: InteractionRecord) => record.id.toString())
              }
              .width('100%')
              .height(200)
            }
          }
          .width('85%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 20, bottom: 20 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
