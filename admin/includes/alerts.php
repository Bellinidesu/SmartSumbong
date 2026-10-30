<?php
/**
 * The kinds of alert an administrator gets, as the profile's Alerts card names them (0136). Each can be turned off
 * on its own (users.muted_notification_kinds, 0044); 'verification' is not here because it cannot be.
 */
declare(strict_types=1);

const ALERT_KINDS = ['escalation', 'sla_warning', 'status_change', 'reroute', 'retirement', 'case_forwarded', 'forward_flag', 'reroute_question', 'inbox_mail'];

/** kind => [name, what it is about], in the reader's language. */
function alert_kinds(): array
{
    return [
        'escalation'    => [t('Overdue cases', 'Lampas sa deadline'), t('A case passed its deadline. It repeats while the case stays overdue.', 'Lumampas sa deadline ang isang kaso. Umuulit habang lampas pa ito.')],
        'sla_warning'   => [t('SMART warnings', 'Babala ng SMART'), t('An urgent case waiting without a tanod, or a case with no update for days.', 'Urgent na kasong walang tanod, o kasong ilang araw nang walang update.')],
        'status_change' => [t('Things for you to do', 'Mga dapat mong gawin'), t('A resident wrote, a tanod filed a resolution, an appeal, or a request to review.', 'Sumulat ang residente, nagpasa ng resolusyon ang tanod, may apela, o may hiling na suriin.')],
        'reroute'       => [t('Dispatch changes', 'Pagbabago sa dispatch'), t('A tanod\'s dispatch was moved to someone else.', 'Inilipat sa iba ang dispatch ng isang tanod.')],
        'retirement'    => [t('Personnel', 'Tauhan'), t('A tanod asked to end their service.', 'Humiling ang isang tanod na tapusin ang serbisyo.')],
        // 0157 (Roles and pages): the committees' own alerts
        'case_forwarded'   => [t('Forwards', 'Mga ipinasa'), t('A case was forwarded to your committee, or to the super admins to place.', 'May kasong ipinasa sa iyong komite, o sa mga super admin para ilagay.')],
        'forward_flag'     => [t('Flags', 'Mga flag'), t('Staff flagged a case for forwarding, or your flag was answered.', 'May in-flag ang kawani para ipasa, o sinagot ang iyong flag.')],
        'reroute_question' => [t('Reroute questions', 'Mga tanong sa reroute'), t('None of your committee\'s tanods is free: pick one before the wait runs out.', 'Walang bakanteng tanod ang iyong komite: pumili bago maubos ang palugit.')],
        'inbox_mail'       => [t('Inbox messages', 'Mga mensahe sa Inbox'), t('Someone wrote to you in the Inbox.', 'May sumulat sa iyo sa Inbox.')],
    ];
}
