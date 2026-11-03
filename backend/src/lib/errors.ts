import type { FastifyError, FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { ZodError } from 'zod';
import { resolveLang, type Lang } from './i18n.js';

/** A message in both languages, or one string for both. */
export type Msg = string | { en: string; ru: string };

export interface ErrorBody {
  error: { code: string; message: string };
}

export class AppError extends Error {
  readonly statusCode: number;
  readonly code: string;
  readonly msg: Msg;
  readonly headers: Record<string, string> | undefined;

  constructor(statusCode: number, code: string, msg: Msg, headers?: Record<string, string>) {
    super(typeof msg === 'string' ? msg : msg.en);
    this.name = 'AppError';
    this.statusCode = statusCode;
    this.code = code;
    this.msg = msg;
    this.headers = headers;
  }
}

export function pickMsg(msg: Msg, lang: Lang): string {
  return typeof msg === 'string' ? msg : msg[lang];
}

export function errorBody(code: string, message: string): ErrorBody {
  return { error: { code, message } };
}

export const invalidRequest = (detail?: string) =>
  new AppError(
    400,
    'invalid_request',
    detail
      ? { en: `Invalid request: ${detail}`, ru: `Некорректный запрос: ${detail}` }
      : { en: 'Invalid request', ru: 'Некорректный запрос' },
  );

export const unauthorized = () =>
  new AppError(401, 'unauthorized', {
    en: 'Please sign in again.',
    ru: 'Войдите заново.',
  });

export const accountInactive = () =>
  new AppError(403, 'account_inactive', {
    en: 'Your subscription is not active. Renew it to continue.',
    ru: 'Подписка неактивна. Продлите её, чтобы продолжить.',
  });

export const notFound = (code = 'not_found', msg?: Msg) =>
  new AppError(404, code, msg ?? { en: 'Not found', ru: 'Не найдено' });

export const conflict = (code: string, msg: Msg) => new AppError(409, code, msg);

const statusCodes: Record<number, { code: string; msg: Msg }> = {
  400: { code: 'invalid_request', msg: { en: 'Invalid request', ru: 'Некорректный запрос' } },
  401: { code: 'unauthorized', msg: { en: 'Please sign in again.', ru: 'Войдите заново.' } },
  403: { code: 'forbidden', msg: { en: 'Access denied', ru: 'Доступ запрещён' } },
  404: { code: 'not_found', msg: { en: 'Not found', ru: 'Не найдено' } },
  405: { code: 'method_not_allowed', msg: { en: 'Method not allowed', ru: 'Метод не поддерживается' } },
  406: { code: 'not_acceptable', msg: { en: 'Not acceptable', ru: 'Формат не поддерживается' } },
  409: { code: 'conflict', msg: { en: 'Conflict', ru: 'Конфликт' } },
  413: { code: 'payload_too_large', msg: { en: 'Payload too large', ru: 'Слишком большой запрос' } },
  415: {
    code: 'unsupported_media_type',
    msg: { en: 'Unsupported content type', ru: 'Неподдерживаемый тип содержимого' },
  },
  429: {
    code: 'rate_limited',
    msg: { en: 'Too many requests. Try again later.', ru: 'Слишком много запросов. Попробуйте позже.' },
  },
};

function describeZod(err: ZodError): string {
  return err.issues
    .slice(0, 3)
    .map((i) => `${i.path.length ? i.path.join('.') : '(root)'}: ${i.message}`)
    .join('; ');
}

export function registerErrorHandling(app: FastifyInstance): void {
  app.setErrorHandler((err: FastifyError | AppError | ZodError | Error, req: FastifyRequest, reply: FastifyReply) => {
    const lang = resolveLang(req.headers['accept-language']);

    if (err instanceof AppError) {
      if (err.headers) void reply.headers(err.headers);
      if (err.statusCode === 500) req.log.error({ err }, 'request failed');
      return reply.code(err.statusCode).send(errorBody(err.code, pickMsg(err.msg, lang)));
    }

    if (err instanceof ZodError) {
      const e = invalidRequest(describeZod(err));
      return reply.code(400).send(errorBody(e.code, pickMsg(e.msg, lang)));
    }

    const fe = err as FastifyError;
    const status = typeof fe.statusCode === 'number' ? fe.statusCode : 500;

    if (status >= 400 && status < 500) {
      const known = statusCodes[status] ?? statusCodes[400]!;
      let message = pickMsg(known.msg, lang);
      // Body parser errors are safe and helpful to surface.
      if (status === 400 && typeof fe.code === 'string' && fe.code.startsWith('FST_ERR_CTP')) {
        message = `${message}: ${fe.message}`;
      }
      return reply.code(status).send(errorBody(known.code, message));
    }

    req.log.error({ err }, 'unhandled error');
    return reply
      .code(500)
      .send(errorBody('internal', lang === 'ru' ? 'Что-то пошло не так. Попробуйте позже.' : 'Something went wrong. Try again later.'));
  });

  app.setNotFoundHandler((req, reply) => {
    const lang = resolveLang(req.headers['accept-language']);
    return reply.code(404).send(errorBody('not_found', lang === 'ru' ? 'Не найдено' : 'Not found'));
  });
}
