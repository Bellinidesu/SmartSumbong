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
