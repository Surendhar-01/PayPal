import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from 'react';
import type { Session, User } from '@supabase/supabase-js';
import { supabase } from '../services/supabase';

export type AppRole = 'customer' | 'merchant';

export interface CustomerProfile {
  taxId: string | null;
  address: string | null;
  phone: string | null;
  status: string | null;
  joinedAt: string | null;
}

export interface MerchantProfile {
  contactName: string | null;
  category: string | null;
  rating: number | null;
  status: string | null;
  factoryLocation: string | null;
  verifiedTier: string | null;
}

export interface AuthenticatedProfile {
  id: string;
  email: string;
  fullName: string | null;
  company: string | null;
  role: AppRole;
  avatarUrl: string | null;
  createdAt: string | null;
  customer: CustomerProfile | null;
  merchant: MerchantProfile | null;
}

interface AuthContextValue {
  session: Session | null;
  user: User | null;
  profile: AuthenticatedProfile | null;
  role: AppRole | null;
  loading: boolean;
  profileLoading: boolean;
  profileError: string | null;
  signIn: (email: string, password: string) => Promise<{ error: string | null }>;
  signUpCustomer: (payload: {
    email: string;
    password: string;
    fullName: string;
    accountType: string;
  }) => Promise<{ error: string | null }>;
  signUpMerchant: (payload: {
    email: string;
    password: string;
    businessName: string;
    ownerName: string;
  }) => Promise<{ error: string | null }>;
  signOut: () => Promise<void>;
  refreshProfile: () => void;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

const isAppRole = (role: unknown): role is AppRole =>
  role === 'customer' || role === 'merchant';

const metadataString = (user: User, ...keys: string[]): string | null => {
  for (const key of keys) {
    const value = user.user_metadata?.[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
  }
  return null;
};

export const profileInitials = (fullName: string | null, email: string): string => {
  const name = fullName?.trim();
  if (name) {
    const parts = name.split(/\s+/);
    return parts.length > 1
      ? `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase()
      : parts[0].slice(0, 2).toUpperCase();
  }
  return email.trim().slice(0, 2).toUpperCase() || 'U';
};

const clearUserScopedDrafts = (userId: string | null = null): void => {
  try {
    sessionStorage.removeItem('markettwin_ai_requirement_conversation_v1');
    sessionStorage.removeItem('markettwin_reviewed_demand_draft_v1');
    sessionStorage.removeItem('markettwin_demand_submission_id_v1');
    sessionStorage.removeItem('markettwin_paypal_checkout_context_v1');
    if (userId) localStorage.removeItem(`markettwin_recent_views_${userId}`);
  } catch (error) {
    console.warn('Unable to clear user-specific browser data.', error);
  }
};

const isSupabaseAuthKey = (key: string): boolean =>
  (key.startsWith('sb-') && key.includes('-auth-token')) || key === 'supabase.auth.token';

const clearStoredSupabaseSession = (): void => {
  const clearStorage = (storage: Storage): void => {
    try {
      const keysToRemove: string[] = [];
      for (let index = 0; index < storage.length; index += 1) {
        const key = storage.key(index);
        if (key && isSupabaseAuthKey(key)) keysToRemove.push(key);
      }
      keysToRemove.forEach((key) => storage.removeItem(key));
    } catch (error) {
      console.warn('Unable to clear stored Supabase session data.', error);
    }
  };

  try {
    clearStorage(window.localStorage);
  } catch (error) {
    console.warn('Unable to access local storage while clearing the session.', error);
  }
  try {
    clearStorage(window.sessionStorage);
  } catch (error) {
    console.warn('Unable to access session storage while clearing the session.', error);
  }
};

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [session, setSession] = useState<Session | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<AuthenticatedProfile | null>(null);
  const [role, setRole] = useState<AppRole | null>(null);
  const [loading, setLoading] = useState(true);
  const [profileLoading, setProfileLoading] = useState(false);
  const [profileError, setProfileError] = useState<string | null>(null);
  const [profileRevision, setProfileRevision] = useState(0);
  const currentUserId = useRef<string | null>(null);
  const refreshProfile = useCallback(() => setProfileRevision((revision) => revision + 1), []);

  useEffect(() => {
    if (!supabase) {
      setLoading(false);
      return;
    }

    let isMounted = true;
    let authEventReceived = false;
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, newSession) => {
      authEventReceived = true;
      const nextUser = newSession?.user ?? null;
      const nextUserId = nextUser?.id ?? null;
      const identityChanged = currentUserId.current !== nextUserId;
      if (identityChanged) {
        if (currentUserId.current !== null) clearUserScopedDrafts(currentUserId.current);
        currentUserId.current = nextUserId;
        setProfile(null);
        setRole(null);
        setProfileError(null);
      }

      setSession(newSession);
      setUser(nextUser);
      setLoading(false);
      if (!nextUser) {
        setProfile(null);
        setRole(null);
        setProfileError(null);
        setProfileLoading(false);
      } else if (identityChanged || event === 'SIGNED_IN' || event === 'USER_UPDATED') {
        setProfileLoading(true);
        if (event === 'SIGNED_IN' || event === 'USER_UPDATED') {
          setProfileRevision((revision) => revision + 1);
        }
      }
    });

    void supabase.auth.getSession().then(({ data, error }) => {
      if (!isMounted || authEventReceived) return;
      if (error) throw error;
      const nextSession = data.session;
      const nextUser = nextSession?.user ?? null;
      currentUserId.current = nextUser?.id ?? null;
      setSession(nextSession);
      setUser(nextUser);
      setProfileLoading(Boolean(nextUser));
      setLoading(false);
    }).catch((error: unknown) => {
      if (!isMounted || authEventReceived) return;
      console.error('Unable to restore the Supabase session.', error);
      setLoading(false);
      setProfileLoading(false);
      setProfileError('Unable to restore your account session. Please sign in again.');
    });

    return () => {
      isMounted = false;
      subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    const client = supabase;
    if (!user || !client) {
      setProfile(null);
      setRole(null);
      setProfileLoading(false);
      return;
    }

    let cancelled = false;
    const userId = user.id;
    const loadProfile = async () => {
      setProfileLoading(true);
      setProfileError(null);

      try {
        const { data: { user: authenticatedUser }, error: authError } = await client.auth.getUser();
        if (authError) throw authError;
        if (!authenticatedUser || authenticatedUser.id !== userId) {
          throw new Error('The active Supabase user does not match the current profile request.');
        }

        const { data: baseProfile, error: baseProfileError } = await client
          .from('profiles')
          .select('id, email, full_name, company, role, created_at')
          .eq('id', authenticatedUser.id)
          .maybeSingle();
        if (baseProfileError) throw baseProfileError;
        if (!baseProfile || !isAppRole(baseProfile.role)) {
          throw new Error('The authenticated account does not have a verified profile role.');
        }

        let customer: CustomerProfile | null = null;
        let merchant: MerchantProfile | null = null;
        if (baseProfile.role === 'customer') {
          const { data, error } = await client
            .from('customer_profiles')
            .select('tax_id, address, phone, status, joined_at')
            .eq('id', authenticatedUser.id)
            .maybeSingle();
          if (error) throw error;
          if (data) {
            customer = {
              taxId: data.tax_id,
              address: data.address,
              phone: data.phone,
              status: data.status,
              joinedAt: data.joined_at,
            };
          }
        } else if (baseProfile.role === 'merchant') {
          const { data, error } = await client
            .from('merchant_profiles')
            .select('contact_name, category, rating, status, factory_location, verified_tier')
            .eq('id', authenticatedUser.id)
            .maybeSingle();
          if (error) throw error;
          if (data) {
            merchant = {
              contactName: data.contact_name,
              category: data.category,
              rating: data.rating === null ? null : Number(data.rating),
              status: data.status,
              factoryLocation: data.factory_location,
              verifiedTier: data.verified_tier,
            };
          }
        }

        if (cancelled) return;
        const email = authenticatedUser.email ?? '';
        const roleSpecificName = merchant?.contactName?.trim() ?? null;
        setUser(authenticatedUser);
        setRole(baseProfile.role);
        setProfile({
          id: authenticatedUser.id,
          email: email ?? '',
          fullName:
            roleSpecificName ||
            baseProfile.full_name?.trim() ||
            metadataString(authenticatedUser, 'full_name'),
          company: baseProfile.company?.trim() || metadataString(authenticatedUser, 'company'),
          role: baseProfile.role,
          avatarUrl: metadataString(authenticatedUser, 'avatar_url', 'picture'),
          createdAt: baseProfile.created_at,
          customer,
          merchant,
        });
      } catch (error) {
        if (cancelled) return;
        console.error('Unable to load the authenticated account profile.', error);
        setProfile(null);
        setRole(null);
        setProfileError('Unable to verify your account profile. Please retry or sign in again.');
      } finally {
        if (!cancelled) setProfileLoading(false);
      }
    };

    void loadProfile();
    return () => {
      cancelled = true;
    };
  }, [user?.id, profileRevision]);

  const signIn = async (email: string, password: string) => {
    if (!supabase) return { error: 'Supabase is not configured.' };
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    return { error: error?.message ?? null };
  };

  const signUpCustomer = async (payload: {
    email: string;
    password: string;
    fullName: string;
    accountType: string;
  }) => {
    if (!supabase) return { error: 'Supabase is not configured.' };
    const { error } = await supabase.auth.signUp({
      email: payload.email,
      password: payload.password,
      options: {
        data: {
          full_name: payload.fullName,
          role: 'customer',
          account_type: payload.accountType,
        },
        emailRedirectTo: `${window.location.origin}/auth/verify-email`,
      },
    });
    return { error: error?.message ?? null };
  };

  const signUpMerchant = async (payload: {
    email: string;
    password: string;
    businessName: string;
    ownerName: string;
  }) => {
    if (!supabase) return { error: 'Supabase is not configured.' };
    const { error } = await supabase.auth.signUp({
      email: payload.email,
      password: payload.password,
      options: {
        data: {
          full_name: payload.ownerName,
          role: 'merchant',
          company: payload.businessName,
        },
        emailRedirectTo: `${window.location.origin}/auth/verify-email`,
      },
    });
    return { error: error?.message ?? null };
  };

  const signOut = async () => {
    const previousUserId = currentUserId.current;
    clearUserScopedDrafts(previousUserId);

    // Clear the authenticated state first so protected routes stop rendering
    // immediately, even if the network request to Supabase is slow.
    currentUserId.current = null;
    setSession(null);
    setUser(null);
    setProfile(null);
    setRole(null);
    setProfileError(null);
    setProfileLoading(false);

    if (!supabase) {
      clearStoredSupabaseSession();
      return;
    }

    try {
      // Global scope revokes every session for this account. Supabase reads
      // the token from storage, so persisted data is cleared only afterwards.
      const { error } = await supabase.auth.signOut({ scope: 'global' });
      if (error) throw error;
    } catch (error) {
      console.warn('Global sign-out failed; clearing the local session instead.', error);
      try {
        const { error: localError } = await supabase.auth.signOut({ scope: 'local' });
        if (localError) throw localError;
      } catch (localError) {
        console.warn('Local sign-out failed; removing stored session data.', localError);
      }
    } finally {
      // A concurrent token refresh can re-persist credentials; guarantee the
      // stored session is cleared once sign-out settles.
      clearStoredSupabaseSession();
    }
  };

  return (
    <AuthContext.Provider
      value={{
        session,
        user,
        profile,
        role,
        loading,
        profileLoading,
        profileError,
        signIn,
        signUpCustomer,
        signUpMerchant,
        signOut,
        refreshProfile,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = (): AuthContextValue => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
};
