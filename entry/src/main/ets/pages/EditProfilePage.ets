// EditProfilePage.ets — 新建/编辑宠物资料（UI 优化版，逻辑不变）
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import picker from '@ohos.file.picker';
import { Pet } from '../model/Pet';
import { getPet, createPet, savePet, setCurrentPetId, createPetWithoutOwner } from '../utils/PetDataManager';
import { Theme } from '../common/Theme';

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
      const params = router.getParams() as Record<string, number | boolean>;
      let petIdValue: number = 0;
      if (params !== null && params !== undefined) {
        if (params['petId'] !== undefined) { petIdValue = params['petId'] as number; }
        if (params['noOwner'] !== undefined) { this.noOwner = params['noOwner'] as boolean; }
      }
      if (petIdValue > 0) {
        this.editingPetId = petIdValue;
        this.isNew = false;
        const pet = await getPet(this.editingPetId);
        if (pet !== null) {
          this.originalPet = pet;
          this.editName = pet.name; this.editBreed = pet.breed; this.editAge = pet.age;
          this.editWeight = pet.weight; this.editGender = pet.gender;
          this.editStatus = pet.adoptionStatus; this.editAvatar = pet.avatar;
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
        Image($rawfile('image/ic_back.svg')).width(22).height(22)
          .fillColor(Theme.TEXT_PRIMARY).onClick(() => router.back());
        Blank();
        Text(this.isNew ? '添加宠物' : '编辑资料').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY);
        Blank();
        Text('').width(22);
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 12 });

      Scroll() {
        Column() {
          // 头像选择
          Column() {
            Text('宠物头像').fontSize(13).fontColor(Theme.TEXT_SECONDARY).width('100%').margin({ bottom: 10 });
            Row() {
              Stack({ alignContent: Alignment.BottomEnd }) {
                if (this.editAvatar !== '') {
                  Image(this.editAvatar).width(80).height(80).borderRadius(40).objectFit(ImageFit.Cover);
                } else {
                  Column() {
                    Image($rawfile('image/tab_pet.svg')).width(40).height(40).fillColor(Theme.PRIMARY);
                  }
                  .width(80).height(80).borderRadius(40).backgroundColor(Theme.PRIMARY_SOFT).justifyContent(FlexAlign.Center);
                }
                Column() {
                  Image($rawfile('image/ic_edit.svg')).width(12).height(12).fillColor(Theme.TEXT_WHITE);
                }
                .width(26).height(26).borderRadius(13).backgroundColor(Theme.PRIMARY).justifyContent(FlexAlign.Center);
              }
              .onClick(() => this.selectAvatar()).margin({ right: 14 });
              Text(this.editAvatar !== '' ? '点击更换头像' : '点击添加头像')
                .fontSize(13).fontColor(Theme.PRIMARY);
            }
          }
          .width('100%').padding(16).backgroundColor(Theme.CARD)
          .borderRadius(Theme.RADIUS_LG).margin({ bottom: 12 })
          .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 });

          // 表单字段
          Column() {
            this.fieldItem('宠物名字', this.editName, (val: string) => { this.editName = val; });
            this.fieldItem('品种', this.editBreed, (val: string) => { this.editBreed = val; });
            this.fieldItem('年龄', this.editAge, (val: string) => { this.editAge = val; });
            this.fieldItem('体重', this.editWeight, (val: string) => { this.editWeight = val; });
            this.fieldItem('性别', this.editGender, (val: string) => { this.editGender = val; });
          }
          .width('100%').padding(16).backgroundColor(Theme.CARD)
          .borderRadius(Theme.RADIUS_LG).margin({ bottom: 12 })
          .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 });

          // 领养状态
          Column() {
            Text('领养状态').fontSize(13).fontColor(Theme.TEXT_SECONDARY).width('100%').margin({ bottom: 10 });
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(['owned', 'adopted', 'fostering', 'available'], (status: string) => {
                Text(this.statusLabel(status))
                  .fontSize(13).fontColor(this.editStatus === status ? Theme.TEXT_WHITE : Theme.TEXT_SECONDARY)
                  .backgroundColor(this.editStatus === status ? Theme.PRIMARY : Theme.CARD_SOFT)
                  .borderRadius(Theme.RADIUS_PILL)
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 }).margin({ right: 8, bottom: 8 })
                  .onClick(() => { this.editStatus = status; });
              });
            }
            .width('100%');
          }
          .width('100%').padding(16).backgroundColor(Theme.CARD)
          .borderRadius(Theme.RADIUS_LG).margin({ bottom: 20 })
          .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 });

          // 保存按钮
          Button('保存')
            .width('100%').height(50).fontSize(16).fontWeight(FontWeight.Medium)
            .backgroundColor(Theme.PRIMARY).borderRadius(Theme.RADIUS_PILL).margin({ bottom: 20 })
            .onClick(async () => {
              if (this.editName.trim() === '') {
                await promptAction.showDialog({ title: '提示', message: '宠物名字不能为空',
                  buttons: [{ text: '确定', color: Theme.PRIMARY }] });
                return;
              }
              const avatar = this.editAvatar !== '' ? this.editAvatar : (this.originalPet?.avatar || '');
              const pet: Pet = {
                id: this.isNew ? 0 : this.editingPetId,
                name: this.editName.trim(), breed: this.editBreed.trim(),
                age: this.editAge.trim(), weight: this.editWeight.trim(),
                gender: this.editGender.trim(), adoptionStatus: this.editStatus, avatar: avatar,
                createTime: this.isNew ? Date.now() : (this.originalPet?.createTime || 0),
                ownerId: this.isNew ? 0 : (this.originalPet?.ownerId || 0)
              };
              let success = false;
              if (this.isNew) {
                let newId: number;
                if (this.noOwner) { newId = await createPetWithoutOwner(pet); }
                else { newId = await createPet(pet); if (newId > 0) { setCurrentPetId(newId); } }
                success = newId > 0;
              } else {
                const rows = await savePet(pet); success = rows > 0;
              }
              if (success) {
                AppStorage.SetOrCreate(PET_UPDATE_KEY, (AppStorage.Get<number>(PET_UPDATE_KEY) ?? 0) + 1);
                await promptAction.showDialog({ title: '保存成功', message: '宠物信息已保存',
                  buttons: [{ text: '确定', color: Theme.SUCCESS }] });
                router.back();
              } else {
                await promptAction.showDialog({ title: '保存失败', message: '保存宠物信息时出现错误',
                  buttons: [{ text: '确定', color: Theme.DANGER }] });
              }
            });
        }
        .width('100%').padding({ left: 16, right: 16 });
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off);
    }
    .width('100%').height('100%').backgroundColor(Theme.BG);
  }

  @Builder
  fieldItem(label: string, value: string, onChange: (val: string) => void) {
    Column() {
      Text(label).fontSize(13).fontColor(Theme.TEXT_SECONDARY).width('100%').margin({ bottom: 6 });
      TextInput({ text: value })
        .width('100%').height(44).backgroundColor(Theme.CARD_SOFT)
        .borderRadius(Theme.RADIUS_SM).padding({ left: 12 }).placeholderColor(Theme.TEXT_TERTIARY)
        .onChange(onChange);
    }
    .width('100%').margin({ bottom: 14 });
  }

  async selectAvatar() {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select();
      if (result && result.photoUris && result.photoUris.length > 0) {
        this.editAvatar = result.photoUris[0];
      }
    } catch (err) {
      console.error('[EditProfilePage] selectAvatar error:', JSON.stringify(err));
      await promptAction.showDialog({ title: '提示', message: '选择头像失败',
        buttons: [{ text: '确定', color: Theme.PRIMARY }] });
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
