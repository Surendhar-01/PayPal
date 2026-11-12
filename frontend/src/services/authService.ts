import { supabase } from './supabase';

export type AppRole = 'customer' | 'merchant';

export interface SignUpPayload {
  email: string;
  password: string;
  fullName: string;
  role: AppRole;
  company?: string;
}

export const signUp = async (payload: SignUpPayload) => {
  if (!supabase) throw new Error('Supabase is not configured.');
  return supabase.auth.signUp({
    email: payload.email,
    password: payload.password,
    options: {
      data: {
        full_name: payload.fullName,
        role: payload.role,
        company: payload.company,
      },
    },
  });
};

export const signIn = async (email: string, password: string) => {
  if (!supabase) throw new Error('Supabase is not configured.');
  return supabase.auth.signInWithPassword({ email, password });
};

export const signOut = async () => {
  if (!supabase) return;
  await supabase.auth.signOut();
};

export const getCurrentUser = async () => {
  if (!supabase) return null;
  const { data } = await supabase.auth.getUser();
  return data.user ?? null;
};