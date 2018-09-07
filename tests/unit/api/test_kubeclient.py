# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import pytest

from promenade import kubeclient

TEST_DATA = [(
    'Multi-facet update',
    {
        "label-a": "value1",
        "label-b": "value2",
        "label-c": "value3",
    },
    {
        "label-a": "value1",
        "label-c": "value4",
        "label-d": "value99",
    },
    {
        "label-b": None,
        "label-c": "value4",
        "label-d": "value99",
    },
),
             (
                 'Add labels when none exist',
                 None,
                 {
                     "label-a": "value1",
                     "label-b": "value2",
                     "label-c": "value3",
                 },
                 {
                     "label-a": "value1",
                     "label-b": "value2",
                     "label-c": "value3",
                 },
             ),
             (
                 'No updates',
                 {
                     "label-a": "value1",
                     "label-b": "value2",
                     "label-c": "value3",
                 },
                 {
                     "label-a": "value1",
                     "label-b": "value2",
                     "label-c": "value3",
                 },
                 {},
             ),
             (
                 'Delete labels',
                 {
                     "label-a": "value1",
                     "label-b": "value2",
                     "label-c": "value3",
                 },
                 {},
                 {
                     "label-a": None,
                     "label-b": None,
                     "label-c": None,
                 },
             ), (
                 'Delete labels when none',
                 None,
                 {},
                 {},
             ),
             (
                 'Avoid kubernetes.io labels Deletion',
                 {
                     "label-a": "value1",
                     "label-b": "value2",
                     "kubernetes.io/hostname": "ubutubox",
                 },
                 {
                     "label-a": "value99",
                 },
                 {
                     "label-a": "value99",
                     "label-b": None,
                 },
             )]


@pytest.mark.parametrize('description,existing_lbl,input_lbl,expected',
                         TEST_DATA)
def test_get_update_labels(description, existing_lbl, input_lbl, expected):
    applied = kubeclient._get_update_labels(existing_lbl, input_lbl)
    assert applied == expected
