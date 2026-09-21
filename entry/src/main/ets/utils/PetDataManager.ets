// PetDataManager.ets — 多宠物数据管理（基于 SQLite）
import { Pet } from '../model/Pet';
import { insertPet, updatePet, deletePet, queryAllPets, getPetById, queryPetsByOwner, queryPetsByStatus } from '../database/DatabaseService';
import { getCurrentUserId } from './UserDataManager';

const CURRENT_PET_KEY: string = 'currentPetId';

export async function createPet(pet: Pet): Promise<number> {
  pet.ownerId = getCurrentUserId();
  pet.adoptionStatus = 'owned';
  return await insertPet(pet);
}

export async function createPetWithoutOwner(pet: Pet): Promise<number> {
  pet.ownerId = 0;
  pet.adoptionStatus = 'available';
  return await insertPet(pet);
}

export { queryPetsByOwner };

export async function savePet(pet: Pet): Promise<number> {
  return await updatePet(pet);
}

export async function removePet(petId: number): Promise<number> {
  return await deletePet(petId);
}

export async function getAllPets(): Promise<Pet[]> {
  return await queryAllPets();
}

export async function getMyPets(): Promise<Pet[]> {
  const userId = getCurrentUserId();
  if (userId <= 0) {
    return [];
  }
  return await queryPetsByOwner(userId);
}

export async function getAvailablePets(): Promise<Pet[]> {
  return await queryPetsByStatus('available');
}

export async function getPet(petId: number): Promise<Pet | null> {
  return await getPetById(petId);
}

// 当前选中宠物 ID，存 AppStorage 方便页面绑定
export function getCurrentPetId(): number {
  return AppStorage.Get<number>(CURRENT_PET_KEY) ?? -1;
}

export function setCurrentPetId(petId: number): void {
  AppStorage.SetOrCreate(CURRENT_PET_KEY, petId);
}

// 领养宠物
export async function adoptPet(pet: Pet): Promise<boolean> {
  const userId = getCurrentUserId();
  if (userId <= 0) {
    return false;
  }
  pet.ownerId = userId;
  pet.adoptionStatus = 'owned';
  const rows = await updatePet(pet);
  return rows > 0;
}

// 为当前用户确保有至少一个宠物（如果没有则创建默认宠物）
export async function ensureDefaultPet(): Promise<void> {
  const userId = getCurrentUserId();
  if (userId <= 0) {
    return;
  }
  
  const myPets = await queryPetsByOwner(userId);
  if (myPets.length === 0) {
    const defaultPet: Pet = {
      id: 0,
      name: '胖宝宝',
      breed: '藏獒',
      age: '2岁',
      weight: '37kg',
      gender: '女孩',
      adoptionStatus: 'owned',
      avatar: '',
      createTime: Date.now(),
      ownerId: userId
    };
    const newId = await insertPet(defaultPet);
    setCurrentPetId(newId);
    AppStorage.SetOrCreate('petName', defaultPet.name);
    console.info('[PetDataManager] Created default pet, id=' + newId.toString());
  } else {
    const currentId = getCurrentPetId();
    const exists = myPets.some(p => p.id === currentId);
    const selectedId = (exists && currentId > 0) ? currentId : myPets[0].id;
    setCurrentPetId(selectedId);
    const pet = await getPetById(selectedId);
    if (pet !== null) {
      AppStorage.SetOrCreate('petName', pet.name);
    }
  }
}
