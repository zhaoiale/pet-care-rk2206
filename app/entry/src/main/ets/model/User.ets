// User.ets — 用户（领养人）数据模型
export interface User {
  id: number;
  username: string;
  password: string;
  name: string;
  phone: string;
  createTime: number;
}

export function userDefault(): User {
  return {
    id: 0,
    username: '',
    password: '',
    name: '',
    phone: '',
    createTime: Date.now()
  };
}
