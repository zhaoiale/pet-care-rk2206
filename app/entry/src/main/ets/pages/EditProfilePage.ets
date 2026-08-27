// EditProfilePage.ets — 新建/编辑宠物资料
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import picker from '@ohos.file.picker';
import { Pet } from '../model/Pet';
import { getPet, createPet, savePet, setCurrentPetId, createPetWithoutOwner } from '../utils/PetDataManager';

const PET_UPDATE_KEY: string = 'petUpdateKey';

@Entry
@Component
struct EditProfilePage {
  @State editName: string = '';
  @State editBreed: string = '';
  @State editAge: string = '';
  @State editWeight: string = '';
  @State editGender: string = '';
  @State editStatus: string = 'available';
  @State editAvatar: string = '';
  @State isNew: boolean = true;
  @State noOwner: boolean = false;
  private editingPetId: number = 0;
  private originalPet: Pet | null = null;

  async aboutToAppear() {
    try {
      // 从 URL 参数获取 petId 和 noOwner
      const params = router.getParams() as Record<string, number | boolean>;
      let petIdValue: number = 0;
      
      if (params !== null && params !== undefined) {
        if (params['petId'] !== undefined) {
          petIdValue = params['petId'] as number;
        }
        if (params['noOwner'] !== undefined) {
          this.noOwner = params['noOwner'] as boolean;
        }
      }
      
      console.info('[EditProfilePage] petIdValue:', petIdValue, 'noOwner:', this.noOwner);
      
      if (petIdValue > 0) {
        this.editingPetId = petIdValue;
        this.isNew = false;
        const pet = await getPet(this.editingPetId);
        console.info('[EditProfilePage] fetched pet:', JSON.stringify(pet));
        if (pet !== null) {
          this.originalPet = pet;
          this.editName = pet.name;
          this.editBreed = pet.breed;
          this.editAge = pet.age;
          this.editWeight = pet.weight;
          this.editGender = pet.gender;
          this.editStatus = pet.adoptionStatus;
          this.editAvatar = pet.avatar;
          console.info('[EditProfilePage] fields updated');
        }
      }
    } catch (err) {
      console.error('[EditProfilePage] aboutToAppear error:', JSON.stringify(err));
    }
  }

  build() {
    Column() {
      // 顶部导航
      Row() {
        Button('返回')
          .fontSize(16)
          .fontColor('#2196F3')
          .onClick(() => router.back())
        Blank()
        Text(this.isNew ? '添加宠物' : '编辑资料')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text('').width(50)
      }
      .width('100%')
      .padding({ left: 15, right: 15, top: 15, bottom: 15 })

      // 编辑表单
      Column() {
        // 头像选择
        Column() {
          Text('宠物头像')
            .fontSize(14)
            .fontColor('#666')
            .width('100%')
            .margin({ bottom: 10 })
          Row() {
            Stack({ alignContent: Alignment.BottomEnd }) {
              Image(this.editAvatar !== '' ? this.editAvatar : $r('app.media.startIcon'))
                .width(80)
                .height(80)
                .borderRadius(40)
                .backgroundColor('#E0E0E0')
              Image($r('app.media.startIcon'))
                .width(24)
                .height(24)
                .backgroundColor('#2196F3')
                .borderRadius(12)
                .padding(4)
            }
            .onClick(() => this.selectAvatar())
            .margin({ right: 15 })
            Text(this.editAvatar !== '' ? '点击更换头像' : '点击添加头像')
              .fontSize(13)
              .fontColor('#2196F3')
          }
        }
        .width('100%')
        .margin({ bottom: 15 })

        this.fieldItem('宠物名字', this.editName, (val: string) => { this.editName = val; })
        this.fieldItem('品种', this.editBreed, (val: string) => { this.editBreed = val; })
        this.fieldItem('年龄', this.editAge, (val: string) => { this.editAge = val; })
        this.fieldItem('体重', this.editWeight, (val: string) => { this.editWeight = val; })
        this.fieldItem('性别', this.editGender, (val: string) => { this.editGender = val; })

        // 领养状态
        Column() {
          Text('领养状态')
            .fontSize(14)
            .fontColor('#666')
            .width('100%')
            .margin({ bottom: 5 })
          Row() {
            ForEach(['owned', 'adopted', 'fostering', 'available'],
              (status: string) => {
                Text(this.statusLabel(status))
                  .fontSize(13)
                  .fontColor(this.editStatus === status ? '#FFF' : '#666')
                  .backgroundColor(this.editStatus === status ? '#2196F3' : '#F0F0F0')
                  .borderRadius(15)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .margin({ right: 8 })
                  .onClick(() => { this.editStatus = status; })
              })
          }
        }
        .width('100%')
        .margin({ top: 10, bottom: 15 })
      }
      .width('90%')
      .margin({ top: 20 })

      // 保存按钮
      Button('保存')
        .width('80%')
        .height(50)
        .fontSize(18)
        .backgroundColor('#4CAF50')
        .borderRadius(25)
        .margin({ top: 40 })
        .onClick(async () => {
          if (this.editName.trim() === '') {
            await promptAction.showDialog({ title: '提示', message: '宠物名字不能为空', buttons: [{ text: '确定', color: '#2196F3' }] });
            return;
          }
          const avatar = this.editAvatar !== '' ? this.editAvatar : (this.originalPet?.avatar || '');
          const pet: Pet = {
            id: this.isNew ? 0 : this.editingPetId,
            name: this.editName.trim(),
            breed: this.editBreed.trim(),
            age: this.editAge.trim(),
            weight: this.editWeight.trim(),
            gender: this.editGender.trim(),
            adoptionStatus: this.editStatus,
            avatar: avatar,
            createTime: this.isNew ? Date.now() : (this.originalPet?.createTime || 0),
            ownerId: this.isNew ? 0 : (this.originalPet?.ownerId || 0)
          };

          let success = false;
          if (this.isNew) {
            let newId: number;
            if (this.noOwner) {
              newId = await createPetWithoutOwner(pet);
            } else {
              newId = await createPet(pet);
              if (newId > 0) {
                setCurrentPetId(newId);
              }
            }
            success = newId > 0;
          } else {
            const rows = await savePet(pet);
            success = rows > 0;
          }

          if (success) {
            AppStorage.SetOrCreate(PET_UPDATE_KEY, (AppStorage.Get<number>(PET_UPDATE_KEY) ?? 0) + 1);
            await promptAction.showDialog({ title: '保存成功', message: '宠物信息已保存', buttons: [{ text: '确定', color: '#4CAF50' }] });
            router.back();
          } else {
            await promptAction.showDialog({ title: '保存失败', message: '保存宠物信息时出现错误', buttons: [{ text: '确定', color: '#F44336' }] });
          }
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  fieldItem(label: string, value: string, onChange: (val: string) => void) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontColor('#666')
        .width('100%')
        .margin({ bottom: 5 })
      TextInput({ text: value })
        .width('100%')
        .height(45)
        .backgroundColor('#F5F5F5')
        .borderRadius(8)
        .onChange(onChange)
    }
    .width('100%')
    .margin({ bottom: 15 })
  }

  async selectAvatar() {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select();
      if (result && result.photoUris && result.photoUris.length > 0) {
        this.editAvatar = result.photoUris[0];
        console.info('[EditProfilePage] Avatar selected:', this.editAvatar);
      }
    } catch (err) {
      console.error('[EditProfilePage] selectAvatar error:', JSON.stringify(err));
      await promptAction.showDialog({ title: '提示', message: '选择头像失败', buttons: [{ text: '确定', color: '#2196F3' }] });
    }
  }

  statusLabel(status: string): string {
    switch (status) {
      case 'owned': return '已领养';
      case 'adopted': return '已收养';
      case 'fostering': return '寄养中';
      case 'available': return '待领养';
      default: return status;
    }
  }
}
