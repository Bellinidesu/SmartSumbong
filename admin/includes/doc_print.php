<?php
/**
 * The barangay's printed documents (30 Sep 2026): the Barangay Complaint
 * Summary and the Certification of Lack of Jurisdiction, laid out like the
 * barangay's own templates — seal left, the four heading lines centred,
 * Bagong Pilipinas right, Letter size.
 *
 * Each page shows the document on screen with a toolbar above it (fill in,
 * then Print); the toolbar never prints. Documents are always English,
 * whatever the portal's language.
 */

declare(strict_types=1);

function doc_head(string $title): void
{
    force_lang('en');
    ?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= e($title) ?> — Barangay 183</title>
<link rel="icon" type="image/png" href="assets/img/brgy-183-seal.png">
<?= theme_head(false) ?>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Urbanist:wght@500;600;700;800&display=swap" rel="stylesheet">
<style>
  @page { size: Letter; margin: 0.6in 0.75in; }
  :root { --ink: #111; --line: #222; --muted: #555; }
  * { box-sizing: border-box; }
  body { margin: 0; background: #e9ecf2; color: var(--ink);
    font-family: "Century Gothic", "Questrial", "Avenir", "Segoe UI", Arial, sans-serif; font-size: 12.5pt; }
  .doc-toolbar { position: sticky; top: 0; z-index: 2; background: #00308f; color: #fff;
    display: flex; flex-wrap: wrap; align-items: center; gap: 10px 16px; padding: 10px 20px; font: 14px "Segoe UI", Arial, sans-serif; }
  .doc-toolbar a { color: #fff; }
  .doc-toolbar label { display: inline-flex; align-items: center; gap: 6px; }
  .doc-toolbar input[type=text], .doc-toolbar input[type=month], .doc-toolbar input[type=date] {
    font: inherit; padding: 5px 8px; border-radius: 6px; border: 0; min-width: 0; }
  .doc-toolbar button { font: inherit; font-weight: 700; padding: 7px 18px; border-radius: 8px; border: 0;
    background: #ff9800; color: #fff; cursor: pointer; }
  .doc-toolbar .spacer { flex: 1; }
  .doc-page { width: 8.5in; min-height: 11in; margin: 24px auto; background: #fff; padding: 0.6in 0.75in;
    box-shadow: 0 2px 14px rgba(0,0,0,.18); }
  .letterhead { display: grid; grid-template-columns: 1.3in 1fr 1.6in; align-items: center; text-align: center; }
  .letterhead img { max-width: 100%; }
  .letterhead .seal { width: 1.2in; }
  .letterhead .bp { width: 1.5in; justify-self: end; }
  .letterhead p { margin: 0; font-size: 12.5pt; line-height: 1.3; }
  .doc-title { text-align: center; font-weight: 700; margin: 0.45in 0 0.35in; font-size: 12.5pt; }
  .fill { font-weight: 700; text-decoration: underline; }
  .req { margin: 0.6in 0 0 auto; width: 2.6in; }
  .req p { margin: 0 0 14px; }
  @media print {
    body { background: #fff; }
    .doc-toolbar { display: none; }
    .doc-page { width: auto; min-height: 0; margin: 0; padding: 0; box-shadow: none; }
  }
</style>
<style>
  /* The portal's look around the document (3 Oct 2026). Screen only: the
     document itself stays a plain official form, and nothing here prints. */
  @media screen {
    :root { --d-bg: #EEF1F7; --d-tex: #00308F; --d-shadow: 0 2px 6px rgba(20,27,52,.10), 0 18px 50px rgba(20,27,52,.16); }
    :root[data-theme="dark"] { --d-bg: #0E1322; --d-tex: #8DB2FF; --d-shadow: 0 2px 6px rgba(0,0,0,.4), 0 18px 50px rgba(0,0,0,.5); color-scheme: dark; }
    body { background: var(--d-bg); position: relative; isolation: isolate; min-height: 100vh; }
    body::before { content: ""; position: fixed; inset: 0; z-index: -1; pointer-events: none; background: var(--d-tex); opacity: .08;
      -webkit-mask: url("assets/img/texture-contours.png") 0 0 / 560px 560px repeat, linear-gradient(to top, #000 0%, rgba(0,0,0,.5) 30%, transparent 60%);
      mask: url("assets/img/texture-contours.png") 0 0 / 560px 560px repeat, linear-gradient(to top, #000 0%, rgba(0,0,0,.5) 30%, transparent 60%);
      -webkit-mask-composite: source-in; mask-composite: intersect; }
    .doc-toolbar { position: sticky; top: 12px; margin: 12px auto 0; max-width: min(1180px, calc(100% - 24px)); border-radius: 18px; padding: 12px 16px; gap: 10px 12px;
      background: linear-gradient(135deg, #00308F, #00236A); box-shadow: 0 10px 30px rgba(0,30,90,.28); font: 600 14px Urbanist, "Segoe UI", Arial, sans-serif;
      overflow: hidden; isolation: isolate; }
    .doc-toolbar::before { content: ""; position: absolute; inset: 0; z-index: -1; background: #fff; opacity: .13;
      -webkit-mask: url("assets/img/texture-contours.png") 0 0 / 420px 420px repeat; mask: url("assets/img/texture-contours.png") 0 0 / 420px 420px repeat; }
    .doc-toolbar > a { display: inline-flex; align-items: center; height: 34px; padding: 0 12px; border-radius: 99px; background: rgba(255,255,255,.12); text-decoration: none; font-weight: 700; }
    .doc-toolbar > a:hover { background: rgba(255,255,255,.2); }
    .doc-toolbar label { gap: 8px; color: rgba(255,255,255,.85); }
    .doc-toolbar input[type=text], .doc-toolbar input[type=month], .doc-toolbar input[type=date] {
      height: 34px; padding: 0 12px; border-radius: 99px; border: 1px solid rgba(255,255,255,.25); background: rgba(255,255,255,.95); color: #141B34; font: 600 13.5px Urbanist, Arial, sans-serif; }
    .doc-toolbar input:focus-visible { outline: 2px solid #FF9800; outline-offset: 1px; }
    /* Reason checkboxes as chips. */
    .doc-toolbar label:has(> input[type=checkbox]) { height: 32px; padding: 0 12px 0 10px; border-radius: 99px; background: rgba(255,255,255,.1); border: 1px solid rgba(255,255,255,.2); cursor: pointer; transition: background .15s; }
    .doc-toolbar label:has(> input[type=checkbox]:checked) { background: #fff; color: #00308F; border-color: #fff; }
    .doc-toolbar input[type=checkbox] { accent-color: #FF9800; width: 15px; height: 15px; margin: 0; }
    .doc-toolbar button { height: 38px; padding: 0 20px; border-radius: 99px; background: #FF9800; box-shadow: 0 4px 12px rgba(255,152,0,.35); font: 800 14px Urbanist, Arial, sans-serif; }
    .doc-toolbar button:hover { background: #F08A00; }
    .doc-page { margin: 28px auto 48px; border-radius: 4px; box-shadow: var(--d-shadow); }
  }
</style>
</head>
<body>
<?php
}

function doc_letterhead(): void
{
    ?>
  <div class="letterhead">
    <img class="seal" src="assets/img/brgy-183-seal.png" alt="Barangay 183 seal">
    <div>
      <p>Republic of the Philippines</p>
      <p>City of Pasay</p>
      <p>Barangay 183, Zone 20</p>
      <p>Villamor, Pasay City</p>
    </div>
    <img class="bp" src="assets/img/bagong-pilipinas.png" alt="Bagong Pilipinas">
  </div>
<?php
}

function doc_requested_by(string $name): void
{
    ?>
  <div class="req">
    <p>Requested by:</p>
    <p class="fill"><?= e($name !== '' ? $name : 'Name of Requestor') ?></p>
  </div>
<?php
}
