import 'package:flutter/material.dart';

/// Paleta de marca V5 — replicada 1:1 do design system do PWA irmão
/// "Remédios na Hora" (`tailwind.config.js` + `src/index.css` do repo
/// alexsantossp71-lgtm/remedios_app).
///
/// Os hexes são os literais do app web para que produto nativo e produto
/// web compartilhem a mesma identidade visual — um usuário que alterna
/// entre os dois reconhece o mesmo produto.
abstract final class BrandColors {
  // ── Ação / marca ────────────────────────────────────────────────────────

  /// `brand.blue` #0f766e — teal de ação: botões, foco, dose pendente.
  static const Color teal700 = Color(0xFF0F766E);

  /// `brand.green` #0d9488 — teal médio de gradientes e estados de foco.
  static const Color teal600 = Color(0xFF0D9488);

  /// #2dd4bf — ciano claro que fecha o gradiente do brand-mark.
  static const Color teal400 = Color(0xFF2DD4BF);

  /// #115e59 — teal profundo que abre o gradiente do herói.
  static const Color heroDeep = Color(0xFF115E59);

  /// `brand.red` #dc4c4c — atraso / ação destrutiva.
  static const Color red = Color(0xFFDC4C4C);

  /// `brand.yellow` #d99a24 — atenção / alerta.
  static const Color yellow = Color(0xFFD99A24);

  // ── Superfícies claras ──────────────────────────────────────────────────

  /// Fundo do app (`body`).
  static const Color canvas = Color(0xFFF4F7F8);

  /// Texto principal (`--app-ink`).
  static const Color ink = Color(0xFF173438);

  /// Texto secundário (`--app-muted`).
  static const Color muted = Color(0xFF647477);

  /// Teal dessaturado de fundos de ícone (`--app-accent-soft`).
  static const Color accentSoft = Color(0xFFE8F6F4);

  /// Borda de painéis e divisores (`--app-line`).
  static const Color line = Color(0xFFE2EBEB);

  /// Preenchimento de inputs (o React usa branco com borda; aqui o
  /// preenchimento sutil da gray-100 cumpre o mesmo papel).
  static const Color inputFill = Color(0xFFF1F5F6);

  // ── Superfícies escuras ─────────────────────────────────────────────────

  /// Fundo escuro do app (`body` no modo escuro).
  static const Color darkCanvas = Color(0xFF0F172A);

  /// Superfície de cartões e painéis escuros.
  static const Color darkSurface = Color(0xFF1E293B);

  /// Texto principal no escuro.
  static const Color darkInk = Color(0xFFE2EEEE);

  /// Texto secundário no escuro.
  static const Color darkMuted = Color(0xFFA6B8B8);

  /// Borda de painéis no escuro.
  static const Color darkLine = Color(0xFF334B4C);

  /// Preenchimento de inputs no escuro (`input` do CSS escuro).
  static const Color darkInputFill = Color(0xFF172733);

  // ── Sombras ─────────────────────────────────────────────────────────────

  /// `box-shadow: soft` — 0 8px 28px rgba(15, 23, 42, 0.06).
  static const Color shadowSoft = Color(0x0F172A);

  /// Sombra projetada do herói — 0 18px 42px rgba(15, 118, 110, 0.16).
  static const Color shadowHero = Color(0xFF0F766E);
}
