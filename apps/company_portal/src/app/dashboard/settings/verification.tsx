'use client';

import { useEffect, useRef, useState, useTransition } from 'react';
import type { TrustStatus } from '@/lib/account';
import { confirmVerification, requestEmailVerification, requestPhoneVerification } from './actions';

const RESEND_COOLDOWN_MS = 30_000;

function Verified() {
  return (
    <span className="pill" style={{ color: 'var(--color-verified)' }}>
      ✓ Verified
    </span>
  );
}

function ErrorText({ children }: { children: React.ReactNode }) {
  return (
    <p className="text-sm mt-2" role="alert" style={{ color: 'var(--color-danger)' }}>
      {children}
    </p>
  );
}

/**
 * One text field for the whole code: paste, SMS/email autofill
 * (one-time-code) and typing all work, and anything that is not a digit is
 * dropped. Submits by itself once six digits are in.
 */
function CodeEntry({
  channel,
  sentTo,
  onResend,
  resendPending,
  resendReady,
  onDone,
}: {
  channel: 'email' | 'phone';
  sentTo?: string;
  onResend: () => void;
  resendPending: boolean;
  resendReady: boolean;
  onDone: () => void;
}) {
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  function submit(value: string) {
    if (value.length !== 6 || pending) return;
    setError(null);
    start(async () => {
      const res = await confirmVerification(channel, value);
      if (res.error) {
        setError(res.error);
        setCode('');
        inputRef.current?.focus();
      } else {
        onDone();
      }
    });
  }

  return (
    <form
      className="mt-3"
      onSubmit={(e) => {
        e.preventDefault();
        submit(code);
      }}
    >
      <p className="text-sm muted">
        We sent a 6-digit code to <span className="font-semibold">{sentTo ?? `your ${channel}`}</span>. It expires in
        15 minutes.
      </p>
      <label className="label mt-3" htmlFor={`${channel}-code`}>
        Code
      </label>
      <div className="flex gap-2 flex-wrap items-center">
        <input
          ref={inputRef}
          id={`${channel}-code`}
          className="input font-mono text-lg tracking-[0.4em] text-center"
          style={{ maxWidth: 190 }}
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="[0-9]{6}"
          maxLength={6}
          placeholder="••••••"
          value={code}
          disabled={pending}
          onChange={(e) => {
            const v = e.target.value.replace(/\D/g, '').slice(0, 6);
            setCode(v);
            if (v.length === 6) submit(v);
          }}
          onPaste={(e) => {
            const v = e.clipboardData.getData('text').replace(/\D/g, '').slice(0, 6);
            if (v) {
              e.preventDefault();
              setCode(v);
              if (v.length === 6) submit(v);
            }
          }}
        />
        <button className="btn btn-primary" disabled={pending || code.length !== 6}>
          {pending ? 'Checking…' : 'Verify'}
        </button>
        <button
          type="button"
          className="text-sm underline muted disabled:no-underline disabled:opacity-60"
          onClick={onResend}
          disabled={resendPending || !resendReady}
        >
          {resendPending ? 'Sending…' : resendReady ? 'Send a new code' : 'New code sent'}
        </button>
      </div>
      {error && <ErrorText>{error}</ErrorText>}
    </form>
  );
}

type Step = { stage: 'idle' } | { stage: 'code'; sentTo?: string } | { stage: 'done' };

function useResendCooldown() {
  const [ready, setReady] = useState(true);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);
  function started() {
    setReady(false);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => setReady(true), RESEND_COOLDOWN_MS);
  }
  return { ready, started };
}

function EmailRow({ trust }: { trust: TrustStatus }) {
  const [step, setStep] = useState<Step>({ stage: 'idle' });
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const cooldown = useResendCooldown();

  const verified = trust.email_verified || step.stage === 'done';

  function send() {
    setError(null);
    start(async () => {
      const res = await requestEmailVerification();
      if (res.error) return setError(res.error);
      if (res.data?.already_verified) return setStep({ stage: 'done' });
      cooldown.started();
      setStep({ stage: 'code', sentTo: res.data?.sent_to });
    });
  }

  return (
    <div className="py-4">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div className="min-w-0">
          <p className="font-semibold">Email</p>
          <p className="text-sm muted truncate">{trust.email ?? 'No email on your account'}</p>
        </div>
        {verified ? (
          <Verified />
        ) : step.stage === 'idle' && trust.email ? (
          <button type="button" className="btn btn-ghost" onClick={send} disabled={pending}>
            {pending ? 'Sending…' : 'Verify email'}
          </button>
        ) : null}
      </div>
      {!verified && step.stage === 'code' && (
        <CodeEntry
          channel="email"
          sentTo={step.sentTo}
          onResend={send}
          resendPending={pending}
          resendReady={cooldown.ready}
          onDone={() => setStep({ stage: 'done' })}
        />
      )}
      {error && <ErrorText>{error}</ErrorText>}
    </div>
  );
}

function PhoneRow({ trust }: { trust: TrustStatus }) {
  const [step, setStep] = useState<Step>({ stage: 'idle' });
  const [phone, setPhone] = useState(trust.phone ?? '');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const cooldown = useResendCooldown();

  const verified = trust.phone_verified || step.stage === 'done';

  function send() {
    setError(null);
    start(async () => {
      const res = await requestPhoneVerification(phone);
      if (res.error) return setError(res.error);
      if (res.data?.already_verified) return setStep({ stage: 'done' });
      cooldown.started();
      setStep({ stage: 'code', sentTo: res.data?.sent_to });
    });
  }

  return (
    <div className="py-4">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div className="min-w-0">
          <p className="font-semibold">Phone</p>
          <p className="text-sm muted truncate">
            {trust.phone ?? (trust.phone_otp_available ? 'Add a number to verify it' : 'Not added')}
          </p>
        </div>
        {verified ? <Verified /> : !trust.phone_otp_available ? <span className="pill">Coming soon</span> : null}
      </div>

      {!verified && trust.phone_otp_available && step.stage === 'idle' && (
        <form
          className="mt-3 flex gap-2 flex-wrap"
          onSubmit={(e) => {
            e.preventDefault();
            send();
          }}
        >
          <label className="sr-only" htmlFor="phone">
            Phone number
          </label>
          <input
            id="phone"
            className="input"
            style={{ maxWidth: 240 }}
            type="tel"
            inputMode="tel"
            autoComplete="tel"
            placeholder="+91 98765 43210"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            required
          />
          <button className="btn btn-ghost" disabled={pending || !phone.trim()}>
            {pending ? 'Sending…' : 'Send code'}
          </button>
        </form>
      )}
      {!verified && step.stage === 'code' && (
        <CodeEntry
          channel="phone"
          sentTo={step.sentTo}
          onResend={send}
          resendPending={pending}
          resendReady={cooldown.ready}
          onDone={() => setStep({ stage: 'done' })}
        />
      )}
      {error && <ErrorText>{error}</ErrorText>}
    </div>
  );
}

export default function Verification({ trust }: { trust: TrustStatus }) {
  return (
    <div>
      <EmailRow trust={trust} />
      <div className="border-t hairline">
        <PhoneRow trust={trust} />
      </div>
    </div>
  );
}
