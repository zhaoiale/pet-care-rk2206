// Pet.ets — 宠物数据模型
export interface Pet {
  id: number;
  name: string;
  breed: string;
  age: string;
  weight: string;
  gender: string;
  adoptionStatus: string;  // 'owned' | 'adopted' | 'available' | 'fostering'
  avatar: string;          // 头像路径，空串用默认图标
  createTime: number;      // Unix 毫秒
  ownerId: number;         // 领养人用户 ID，0 表示未被领养
}

export function petDefaultAvatar(): string {
  return '';
}

export function petAdoptionLabel(status: string): string {
  switch (status) {
    case 'owned': return '已领养';
    case 'adopted': return '已收养';
    case 'available': return '待领养';
    case 'fostering': return '寄养中';
    default: return status;
  }
}

export function isCat(breed: string): boolean {
  return breed.includes('猫');
}
