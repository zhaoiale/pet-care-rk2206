// UserDataManager.ets — 用户数据管理器
import { User } from '../model/User';
import { insertUser, getUserByUsername, getUserById, updateUser, queryAllUsers, deleteUser } from '../database/DatabaseService';

const CURRENT_USER_KEY: string = 'currentUserId';

export async function registerUser(username: string, password: string, name: string, phone: string): Promise<number> {
  const existingUser = await getUserByUsername(username);
  if (existingUser !== null) {
    console.error('[UserManager] Username already exists');
    return -1;
  }
  const user: User = {
    id: 0,
    username: username,
    password: password,
    name: name,
    phone: phone,
    createTime: Date.now()
  };
  return await insertUser(user);
}

export async function loginUser(username: string, password: string): Promise<User | null> {
  const user = await getUserByUsername(username);
  if (user !== null && user.password === password) {
    setCurrentUserId(user.id);
    return user;
  }
  return null;
}

export function logoutUser(): void {
  AppStorage.SetOrCreate(CURRENT_USER_KEY, 0);
}

export function getCurrentUserId(): number {
  return AppStorage.Get<number>(CURRENT_USER_KEY) ?? 0;
}

export function setCurrentUserId(userId: number): void {
  AppStorage.SetOrCreate(CURRENT_USER_KEY, userId);
}

export async function getCurrentUser(): Promise<User | null> {
  const userId = getCurrentUserId();
  if (userId <= 0) {
    return null;
  }
  return await getUserById(userId);
}

export async function updateCurrentUser(name: string, phone: string, password?: string): Promise<boolean> {
  const userId = getCurrentUserId();
  if (userId <= 0) {
    return false;
  }
  const user = await getUserById(userId);
  if (user === null) {
    return false;
  }
  user.name = name;
  user.phone = phone;
  if (password !== undefined && password !== '') {
    user.password = password;
  }
  const rows = await updateUser(user);
  return rows > 0;
}

export function isLoggedIn(): boolean {
  return getCurrentUserId() > 0;
}

export async function getAllUsers(): Promise<User[]> {
  return await queryAllUsers();
}

export async function removeUser(userId: number): Promise<number> {
  return await deleteUser(userId);
}

export { getUserById, getUserByUsername, updateUser };
