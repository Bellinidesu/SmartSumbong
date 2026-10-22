"""python -m unittest discover engine   (stdlib only: the reader needs no model)"""
import unittest

from reader import fuzzy_contains, id_number, read_card, top_down


class ReadCard(unittest.TestCase):
    def test_philsys_with_its_labels(self):
        lines = ['REPUBLIKA NG PILIPINAS', 'PAMBANSANG PAGKAKAKILANLAN', 'Philippine Identification Card', '5376-3269-4049-1105',
                 'Apelyido / Last Name', 'VILLANUEVA', 'Mga Pangalan / Given Names', 'RICHARD', 'Gitnang Apelyido / Middle Name',
                 'PEREZ', 'Petsa ng Kapanganakan / Date of Birth', 'JANUARY 15, 1990']
        self.assertEqual(read_card(lines), {'type': 'philsys', 'name': 'VILLANUEVA RICHARD PEREZ', 'number': '5376-3269-4049-1105'})

    def test_labels_lost_to_blur_still_give_the_name(self):
        lines = ['REPUBLIKA NG PILIPINAS', 'PAMBANSANG PAGKAKAKILANLAN', '9684-1475-8628-5080', 'RAMOS', 'KRISTINE JOY', 'PEREZ', 'JANUARY 15, 1990']
        self.assertEqual(read_card(lines)['name'], 'RAMOS KRISTINE JOY PEREZ')

    def test_one_label_over_one_line_is_read_once(self):
        lines = ['LAND TRANSPORTATION OFFICE', "DRIVER'S LICENSE", 'Last Name, First Name, Middle Name', 'BAUTISTA, MA. TERESA LIM',
                 'License No.', 'K11-43-581195']
        self.assertEqual(read_card(lines), {'type': 'drivers_license', 'name': 'BAUTISTA MA. TERESA LIM', 'number': 'K11-43-581195'})

    def test_a_slip_in_a_label(self):
        lines = ['PHILIPPINE POSTAL CORPORATION', 'POSTAL IDENTITY CARD', 'PRN 680445687345', 'Given Name(s)', 'RICHARD', 'Sumame',
                 'VILLANUEVA', 'Middle Name', 'TAN']
        out = read_card(lines)
        self.assertEqual(out['type'], 'postal_id')
        self.assertIn('VILLANUEVA', out['name'])
        self.assertIn('RICHARD', out['name'])

    def test_headings_are_never_the_name(self):
        out = read_card(['REPUBLIC OF THE PHILIPPINES', 'DEPARTMENT OF TRANSPORTATION', 'LAND TRANSPORTATION OFFICE', 'K80-57-132854'])
        self.assertIsNone(out['name'])

    def test_too_little_text_is_unreadable(self):
        self.assertEqual(read_card(['A1', '', 'ok']), {'type': None, 'name': None, 'number': None})

    def test_masthead_alone_is_no_kind(self):
        self.assertIsNone(read_card(['REPUBLIKA NG PILIPINAS', 'JUAN DELA CRUZ', '1234-5678'])['type'])


class Pieces(unittest.TestCase):
    def test_fuzzy(self):
        self.assertTrue(fuzzy_contains('PAMBANSANG PAGKAKAKILANLAM', 'PAMBANSANG PAGKAKAKILANLAN'))
        self.assertFalse(fuzzy_contains('TANOD', 'TAMOD'))   # short words must match exactly

    def test_numbers(self):
        self.assertEqual(id_number('No. N01-23-456789'), 'N01-23-456789')
        self.assertEqual(id_number('PRN 405622415499'), '405622415499')
        self.assertIsNone(id_number('Zone 20, 183'))

    def test_top_down(self):
        boxes = [[[0, 50], [9, 50], [9, 60], [0, 60]], [[0, 10], [9, 10], [9, 20], [0, 20]]]
        self.assertEqual(top_down(['second', 'first'], boxes), ['first', 'second'])


if __name__ == '__main__':
    unittest.main()
