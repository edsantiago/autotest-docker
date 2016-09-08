#!/usr/bin/env python

import json
import unittest
import sys
import types


def mock(mod_path):
    name_list = mod_path.split('.')
    child_name = name_list.pop()
    child_mod = sys.modules.get(mod_path, types.ModuleType(child_name))
    if len(name_list) == 0:  # child_name is left-most basic module
        if child_name not in sys.modules:
            sys.modules[child_name] = child_mod
        return sys.modules[child_name]
    else:
        # New or existing child becomes parent
        recurse_path = ".".join(name_list)
        parent_mod = mock(recurse_path)
        if not hasattr(sys.modules[recurse_path], child_name):
            setattr(parent_mod, child_name, child_mod)
            # full-name also points at child module
            sys.modules[mod_path] = child_mod
        return sys.modules[mod_path]

# Mock module and exception class in one stroke
setattr(mock('autotest.client.shared.error'), 'CmdError', Exception)
setattr(mock('autotest.client.shared.error'), 'TestFail', Exception)
setattr(mock('autotest.client.shared.error'), 'TestError', Exception)
setattr(mock('autotest.client.shared.error'), 'TestNAError', Exception)
setattr(mock('autotest.client.shared.error'), 'AutotestError', Exception)
mock('autotest.client.utils')
mock('autotest.client.shared.utils')
mock('autotest.client.shared.error')
mock('autotest.client.shared.service')


class DDTestBase(unittest.TestCase):

    def setUp(self):
        import docker_daemon
        self.dd = docker_daemon


class DDTest(DDTestBase):

    def test_client_base(self):
        cb = self.dd.ClientBase('uri')
        self.assertEqual(cb.interface, None)
        self.assertEqual(cb.uri, 'uri')
        self.assertRaises(NotImplementedError, cb.get, 'foo')
        self.assertRaises(NotImplementedError, cb.value_to_json, 'bar')
        self.assertRaises(NotImplementedError, cb.get_json, 'foobar')

    def test_client_subclass(self):
        class c(self.dd.ClientBase):

            def get(self, resource):
                return (self.uri, resource)

            @staticmethod
            def value_to_json(value):
                return json.loads('[{"%s":"%s"}]' % value)
        i = c('foo')
        self.assertEqual(i.get_json('bar'), [{u'foo': u'bar'}])
        self.assertEqual(i.interface, None)


class TestStringEdit(unittest.TestCase):
    pass

    def test_bad_input_no_prefix(self):
        import docker_daemon
        self.assertRaises(ValueError,
                          docker_daemon.edit_options_string, "OPTINOS=hi")

    def test_bad_input_mismatched_quotes(self):
        import docker_daemon
        self.assertRaises(ValueError,
                          docker_daemon.edit_options_string,
                          "OPTIONS='missing end quote")


# Various combinations of inputs, and their expected output for
# the edit_options_string() function.
string_edit_tests = [
    # original          remove          add             expected
    [ 'abc',            None,           None,           'abc'           ],
    [ '"abc"',          None,           None,           '"abc"'         ],
    [ '"abc"',          "abc",          "def",          '"def"'         ],
    [ "'--a --b --c'",  '--a',          None,           "'--b --c'"     ],
    [ "'--a --b --c'",  '--b',          None,           "'--a  --c'"    ],
    [ "'--a --b --c'",  '--c',          None,           "'--a --b'"     ],
    [ "'--a --b --c'",  ['--a', '--c'], None,           "'--b'"         ],
    [ "'--a --c'",      None,           ['--a', '--b'], "'--a --c --b'" ],
]


def test_generator_string_edit(s_in, remove, add, out_expected):
    """
    Return a test function that calls edit_options_string() with the
    given arguments and confirms that its return value is as expected.
    """
    def test(self):
        import docker_daemon
        out_actual = docker_daemon.edit_options_string(s_in, remove, add)
        self.assertEqual(out_actual, out_expected)
    return test


if __name__ == '__main__':
    # Generate a test_NNN function for each test case in table above
    for i, t in enumerate(string_edit_tests):
        test_name = 'test_%03d' % i
        test_ref = test_generator_string_edit("OPTIONS=%s\n" % t[0],
                                              t[1], t[2],
                                              "OPTIONS=%s\n" % t[3])
        setattr(TestStringEdit, test_name, test_ref)

    unittest.main()
